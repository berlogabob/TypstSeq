import 'dart:io';

import 'package:tylog_core/tylog_core.dart';

Future<void> main(List<String> arguments) async {
  try {
    exitCode = await runTylog(arguments);
  } on _UsageException catch (error) {
    stderr.writeln(error.message);
    stderr.writeln(_usage);
    exitCode = 64;
  } catch (error) {
    stderr.writeln('tylog: $error');
    exitCode = 1;
  }
}

Future<int> runTylog(List<String> arguments) async {
  if (arguments.isEmpty || arguments.first == '--help') {
    stdout.writeln(_usage);
    return 0;
  }
  final command = arguments.first;
  final args = arguments.skip(1).toList();
  return switch (command) {
    'init' => _init(args),
    'index' => _index(args),
    'doctor' => _doctor(args),
    'dedupe' => _dedupe(args),
    'export' => _export(args),
    _ => throw _UsageException('Unknown command: $command'),
  };
}

Future<int> _init(List<String> args) async {
  if (args.length > 1) throw _UsageException('init accepts one vault path');
  final root = Directory(args.firstOrNull ?? '.').absolute;
  final assets = await _RepositoryAssets.load();
  await initializeVaultStorage(
    LocalVaultStorage(root),
    managedFiles: assets.managedFiles,
    currentHelper: assets.currentHelper,
    legacyHelper: assets.legacyHelper,
  );
  stdout.writeln('Initialized TyLog v5 vault at ${root.path}');
  return 0;
}

Future<int> _index(List<String> args) async {
  final force = args.remove('--force');
  if (args.length > 1 || args.any((arg) => arg.startsWith('--'))) {
    throw _UsageException('index accepts [vault] [--force]');
  }
  final root = Directory(args.firstOrNull ?? '.').absolute;
  final storage = LocalVaultStorage(root);
  await _openVault(storage);
  VaultIndex? previous;
  if (!force && await storage.exists(TylogVaultPaths.index)) {
    try {
      previous = decodeVaultIndexBytes(
        await storage.readBytes(TylogVaultPaths.index),
      );
    } catch (_) {}
  }
  final previousSearch = await PkmsSearchIndex.loadStorage(
    storage,
    TylogVaultPaths.searchIndex,
  );
  final index = await scanVaultStorage(
    storage,
    inspector: CliTypstInspector(root),
    previous: previous,
    force: force,
  );
  await storage.writeBytes(TylogVaultPaths.index, encodeVaultIndexBytes(index));
  final search = await PkmsSearchIndex.buildStorage(
    storage,
    index,
    previous: previousSearch,
  );
  await search.saveStorage(storage, TylogVaultPaths.searchIndex);
  stdout.writeln(
    'Indexed ${index.notes.length} notes and ${index.tasks.length} tasks '
    '(${index.problems.length} warnings)',
  );
  for (final problem in index.problems) {
    stderr.writeln(
      '${problem.severity.name}: ${problem.subject}: ${problem.message}',
    );
  }
  return 0;
}

Future<int> _doctor(List<String> args) async {
  if (args.length > 1) throw _UsageException('doctor accepts one vault path');
  final root = Directory(args.firstOrNull ?? '.').absolute;
  final storage = LocalVaultStorage(root);
  await _openVault(storage);
  final index = await scanVaultStorage(
    storage,
    inspector: CliTypstInspector(root),
    force: true,
  );
  final report = await validatePkmsStorage(storage, index);
  for (final problem in report.problems) {
    stdout.writeln(
      '${problem.severity.name}: ${problem.code}: ${problem.subject}: ${problem.message}',
    );
  }
  stdout.writeln(report.summary());
  return report.problems.any(
        (problem) => problem.severity == PkmsSeverity.error,
      )
      ? 1
      : 0;
}

Future<int> _dedupe(List<String> args) async {
  final apply = args.remove('--apply');
  if (args.length != 1 || args.any((arg) => arg.startsWith('--'))) {
    throw _UsageException('dedupe requires <vault> [--apply]');
  }
  final storage = LocalVaultStorage(Directory(args.single).absolute);
  if ((await inspectVaultStorage(storage)).kind !=
      VaultStorageKind.validVault) {
    throw StateError('TyLog vault marker is missing or invalid');
  }
  final index = await scanVaultStorage(storage, force: true);
  final groups = <String, List<NoteRef>>{};
  for (final note in index.notes) {
    groups.putIfAbsent(note.id, () => []).add(note);
  }
  final duplicates =
      groups.entries.where((entry) => entry.value.length > 1).toList()
        ..sort((a, b) => a.key.compareTo(b.key));
  var deletions = 0;
  var merges = 0;
  var reassigned = 0;
  var skipped = 0;

  for (final group in duplicates) {
    final id = group.key;
    final owners = group.value..sort((a, b) => a.path.compareTo(b.path));
    final hashes = owners
        .map((note) => note.properties['import_sha256'])
        .whereType<String>()
        .toList();
    if (owners.every((note) => note.path.startsWith('articles/')) &&
        hashes.length == owners.length &&
        hashes.every((hash) => hash.isNotEmpty) &&
        hashes.toSet().length == 1) {
      final modified = <String, DateTime>{};
      for (final note in owners) {
        modified[note.path] =
            (await storage.stat(note.path))?.modified ?? DateTime(0);
      }
      owners.sort((a, b) => _compareArticleOwners(a, b, modified));
      final keep = owners.first.path;
      final remove = owners.skip(1).map((note) => note.path).toList();
      if (apply) {
        for (final path in remove) {
          await storage.delete(path);
        }
      }
      deletions += remove.length;
      stdout.writeln(
        '$id | ${apply ? 'applied' : 'dry-run'}: keep $keep, delete ${remove.join(', ')}',
      );
      continue;
    }

    final canonical = _dailyCanonicalPath(id);
    final twinPattern = canonical == null
        ? null
        : RegExp(
            '^${RegExp.escape(canonical.substring(0, canonical.length - 4))}-[^/]+\\.typ\$',
          );
    final canonicalNotes = canonical == null
        ? const <NoteRef>[]
        : owners.where((note) => note.path == canonical).toList();
    final twins = twinPattern == null
        ? const <NoteRef>[]
        : owners.where((note) => twinPattern.hasMatch(note.path)).toList();
    if (canonicalNotes.length == 1 &&
        twins.isNotEmpty &&
        canonicalNotes.length + twins.length == owners.length) {
      final bodies = <String>[];
      String? bodyError;
      for (final twin in twins) {
        final body = _dailyBody(await storage.readText(twin.path));
        if (body == null) {
          bodyError = '${twin.path} has no title heading';
          break;
        }
        bodies.add(body);
      }
      if (bodyError == null) {
        if (apply) {
          var source = await storage.readText(canonical!);
          for (final body in bodies) {
            source += '\n== Merged from duplicate\n\n$body\n';
          }
          await storage.writeText(canonical, source);
          for (final twin in twins) {
            await storage.delete(twin.path);
          }
        }
        deletions += twins.length;
        merges += twins.length;
        stdout.writeln(
          '$id | ${apply ? 'applied' : 'dry-run'}: merge ${twins.map((note) => note.path).join(', ')} into $canonical',
        );
        continue;
      }
      stdout.writeln('$id | skipped: $bodyError');
      skipped++;
      continue;
    }

    // Id collision: different articles that derived the same id (weak id
    // source in the producer). Content differs, so nothing may be deleted —
    // reassign fresh unique ids to all but the oldest owner instead.
    if (owners.every((note) => note.path.startsWith('articles/')) &&
        owners.map((note) => note.title).toSet().length == owners.length) {
      final modified = <String, DateTime>{};
      for (final note in owners) {
        modified[note.path] =
            (await storage.stat(note.path))?.modified ?? DateTime(0);
      }
      owners.sort((a, b) {
        final byTime = modified[a.path]!.compareTo(modified[b.path]!);
        return byTime != 0 ? byTime : a.path.compareTo(b.path);
      }); // oldest keeps the id
      final renames = <String>[];
      var counter = 2;
      for (final note in owners.skip(1)) {
        String candidate;
        do {
          candidate = '$id-${counter++}';
        } while (groups.containsKey(candidate));
        groups[candidate] = [note];
        if (apply) {
          final source = await storage.readText(note.path);
          final draft = NoteMetadataDraft.fromNote(note);
          await storage.writeText(
            note.path,
            replaceNoteHeader(
              source,
              NoteMetadataDraft(
                id: candidate,
                title: draft.title,
                kind: draft.kind,
                project: draft.project,
                date: draft.date,
                tags: draft.tags,
                aliases: draft.aliases,
                properties: draft.properties,
              ),
            ),
          );
        }
        renames.add('${note.path} -> $candidate');
      }
      reassigned += renames.length;
      stdout.writeln(
        '$id | ${apply ? 'applied' : 'dry-run'}: reassign ${renames.join('; ')}',
      );
      continue;
    }

    final reason = owners.every((note) => note.path.startsWith('articles/'))
        ? 'identical titles with differing content — merge by hand'
        : canonical != null
        ? 'ambiguous daily layout'
        : 'duplicate layout is not safely deduplicatable';
    stdout.writeln('$id | skipped: $reason');
    skipped++;
  }
  stdout.writeln(
    'Summary: groups=${duplicates.length} deletions=$deletions merges=$merges reassigned=$reassigned skipped=$skipped',
  );
  return 0;
}

int _compareArticleOwners(
  NoteRef a,
  NoteRef b,
  Map<String, DateTime> modified,
) {
  final aStem = _stem(a.path);
  final bStem = _stem(b.path);
  final preferred = _preferredArticleStem(
    bStem,
  ).compareTo(_preferredArticleStem(aStem));
  if (preferred != 0) return preferred;
  final length = bStem.length.compareTo(aStem.length);
  if (length != 0) return length;
  final newer = modified[b.path]!.compareTo(modified[a.path]!);
  return newer != 0 ? newer : a.path.compareTo(b.path);
}

int _preferredArticleStem(String stem) {
  final lower = stem.toLowerCase();
  final generic =
      lower == 'home' ||
      lower == 'index' ||
      RegExp(
        r'^[a-z0-9](?:[a-z0-9-]*[a-z0-9])?(?:\.[a-z0-9](?:[a-z0-9-]*[a-z0-9])?)+$',
        caseSensitive: false,
      ).hasMatch(stem);
  return !RegExp(r' \(\d+\)$').hasMatch(stem) && !generic ? 1 : 0;
}

String _stem(String path) =>
    path.split('/').last.replaceFirst(RegExp(r'\.typ$'), '');

String? _dailyCanonicalPath(String id) {
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(id)) return null;
  return 'daily/${id.substring(0, 4)}/${id.substring(5, 7)}/$id.typ';
}

String? _dailyBody(String source) {
  final heading = RegExp(
    r'^= [^\r\n]*(?:\r?\n|$)',
    multiLine: true,
  ).firstMatch(source);
  if (heading == null) return null;
  return source
      .substring(heading.end)
      .replaceFirst(RegExp(r'^(?:[ \t]*\r?\n)+'), '');
}

Future<int> _export(List<String> args) async {
  if (args.isEmpty || args.length > 2) {
    throw _UsageException('export requires <file.typ> [output.pdf]');
  }
  final input = File(args.first).absolute;
  if (!await input.exists()) {
    throw StateError('Input does not exist: ${input.path}');
  }
  final output = File(
    args.length == 2
        ? args[1]
        : input.path.replaceFirst(RegExp(r'\.typ$'), '.pdf'),
  ).absolute;
  final root = await _vaultRoot(input.parent);
  final ProcessResult result;
  try {
    result = await Process.run('typst', [
      'compile',
      '--root',
      root.path,
      input.path,
      output.path,
    ]);
  } on ProcessException catch (error) {
    throw StateError(
      'Typst executable not found; install Typst 0.15.0 or newer (${error.message})',
    );
  }
  if (result.exitCode != 0) {
    throw StateError(result.stderr.toString().trim());
  }
  stdout.writeln('Exported ${output.path}');
  return 0;
}

Future<void> _openVault(LocalVaultStorage storage) async {
  final assets = await _RepositoryAssets.load();
  await initializeVaultStorage(
    storage,
    managedFiles: assets.managedFiles,
    currentHelper: assets.currentHelper,
    legacyHelper: assets.legacyHelper,
    createIfMissing: false,
  );
}

Future<Directory> _vaultRoot(Directory start) async {
  var current = start.absolute;
  while (true) {
    if (await File('${current.path}/.tylog/settings.json').exists()) {
      return current;
    }
    final parent = current.parent;
    if (parent.path == current.path) return start.absolute;
    current = parent;
  }
}

class _RepositoryAssets {
  const _RepositoryAssets({
    required this.managedFiles,
    required this.currentHelper,
    required this.legacyHelper,
  });

  final Map<String, List<int>> managedFiles;
  final String currentHelper;
  final String legacyHelper;

  static Future<_RepositoryAssets> load() async {
    final root = _findRepositoryRoot();
    final vaultAssets = Directory('${root.path}/typst/vault');
    final package = Directory('${root.path}/typst/tylog');
    final current = File('${vaultAssets.path}/tylog.typ');
    final legacy = File('${vaultAssets.path}/legacy-v5-tylog.typ');
    if (!await current.exists() || !await package.exists()) {
      throw StateError('TyLog repository Typst assets are unavailable');
    }
    final files = <String, List<int>>{
      TylogVaultPaths.helper: await current.readAsBytes(),
      TylogVaultPaths.theme: await File(
        '${vaultAssets.path}/theme.typ',
      ).readAsBytes(),
      TylogVaultPaths.export: await File(
        '${vaultAssets.path}/export.typ',
      ).readAsBytes(),
    };
    final toml = await File('${package.path}/typst.toml').readAsString();
    final versionMatch = RegExp(
      r'^version\s*=\s*"(\d+\.\d+\.\d+)"',
      multiLine: true,
    ).firstMatch(toml);
    if (versionMatch == null) {
      throw StateError('typst/tylog/typst.toml has no version field');
    }
    final version = versionMatch[1]!;
    await for (final entity in package.list(recursive: true)) {
      if (entity is! File) continue;
      final relative = entity.absolute.path
          .substring(package.absolute.path.length + 1)
          .replaceAll(Platform.pathSeparator, '/');
      // The app bundles typst/tylog/ non-recursively, so vaults it manages
      // never contain examples/. Match that here or the two writers fight.
      if (relative.startsWith('examples/')) continue;
      files['_system/packages/tylog/$version/$relative'] = await entity
          .readAsBytes();
    }
    return _RepositoryAssets(
      managedFiles: files,
      currentHelper: await current.readAsString(),
      legacyHelper: await legacy.readAsString(),
    );
  }
}

Directory _findRepositoryRoot() {
  final configured = Platform.environment['TYLOG_REPOSITORY_ROOT'];
  if (configured != null && configured.isNotEmpty) {
    return Directory(configured).absolute;
  }
  for (final start in [
    Directory.current,
    File.fromUri(Platform.script).parent,
  ]) {
    var current = start.absolute;
    while (true) {
      if (Directory('${current.path}/typst/tylog').existsSync()) return current;
      final parent = current.parent;
      if (parent.path == current.path) break;
      current = parent;
    }
  }
  throw StateError(
    'Run the repository-local CLI from the TypstSeq checkout or set TYLOG_REPOSITORY_ROOT',
  );
}

class _UsageException implements Exception {
  const _UsageException(this.message);
  final String message;
}

const _usage = '''TyLog repository CLI

Usage:
  tylog init [vault=.]
  tylog index [vault=.] [--force]
  tylog doctor [vault=.]
  tylog dedupe <vault> [--apply]
  tylog export <file.typ> [output.pdf]''';
