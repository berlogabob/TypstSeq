import 'dart:convert';
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
      previous = VaultIndex.fromJson(
        (jsonDecode(await storage.readText(TylogVaultPaths.index)) as Map)
            .cast<String, Object?>(),
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
  await storage.writeText(
    TylogVaultPaths.index,
    const JsonEncoder.withIndent('  ').convert(index.toJson()),
  );
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
    await for (final entity in package.list(recursive: true)) {
      if (entity is! File) continue;
      final relative = entity.absolute.path
          .substring(package.absolute.path.length + 1)
          .replaceAll(Platform.pathSeparator, '/');
      files['_system/packages/tylog/0.1.0/$relative'] = await entity
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
  tylog export <file.typ> [output.pdf]''';
