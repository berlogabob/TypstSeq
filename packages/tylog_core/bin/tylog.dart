import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';

import 'package:tylog_core/tylog_core.dart';
import 'mcp.dart';

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
    'import-contacts' => _importContacts(args),
    'index' => _index(args),
    'cluster' => _cluster(args),
    'eval-links' => _evalLinks(args),
    'doctor' => _doctor(args),
    'vault-health' => _vaultHealth(args),
    'dedupe' => _dedupe(args),
    'migrate-mentions' => _migrateMentions(args),
    'export' => _export(args),
    'pack-validate' => _packValidate(args),
    'mcp' => _mcp(args),
    _ => throw _UsageException('Unknown command: $command'),
  };
}

Future<int> _mcp(List<String> args) async {
  if (args.length != 1 || args.single.startsWith('--')) {
    throw _UsageException('mcp requires <vault>');
  }
  await serveMcp(Directory(args.single).absolute, stdin, stdout);
  return 0;
}

Future<int> _vaultHealth(List<String> args) async {
  if (args.length != 1 || args.single.startsWith('--')) {
    throw _UsageException('vault-health requires <vault>');
  }
  final root = Directory(args.single).absolute;
  final report = await generateHealthReport(root);
  final data = jsonDecode(report) as Map;
  stdout.writeln(
    'Scanned ${data['scanned']} notes; ${(data['issues'] as List).length} findings: ${root.path}/_system/health/${data['date']}.json',
  );
  for (final issue in data['issues'] as List) {
    stdout.writeln('${issue['code']}: ${issue['path']}');
  }
  return 0;
}

Future<String> generateHealthReport(Directory root) async {
  if ((await inspectVaultStorage(LocalVaultStorage(root))).kind !=
      VaultStorageKind.validVault) {
    throw StateError('TyLog vault marker is missing or invalid');
  }
  final issues = <Map<String, String>>[];
  var scanned = 0;
  final noteFiles = <String, File>{};
  // Match the indexer's note roots; managed Typst packages are not notes.
  for (final name in [
    'daily',
    'notes',
    'projects',
    'articles',
    'screenshots',
    'ext',
  ]) {
    final directory = Directory('${root.path}/$name');
    if (!await directory.exists()) continue;
    await for (final entry in directory.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entry is! File || !entry.path.endsWith('.typ')) continue;
      final path = entry.path
          .substring(root.path.length + 1)
          .replaceAll(Platform.pathSeparator, '/');
      noteFiles[path] = entry;
      scanned++;
      String source;
      try {
        source = await entry.readAsString();
      } on FileSystemException {
        issues.add({'path': path, 'code': 'unreadable'});
        continue;
      } on FormatException {
        issues.add({'path': path, 'code': 'unreadable'});
        continue;
      }
      if (!RegExp(r'#show\s*:\s*tylog\.note\.with\s*\(').hasMatch(source)) {
        issues.add({'path': path, 'code': 'missing-note-header'});
      }
      if (source.split('\n').any(_isAutoEntitiesMarkerLine)) {
        issues.add({'path': path, 'code': 'auto-entities'});
      }
    }
  }
  final typstCompile = await _checkTypstBatch(root, noteFiles, issues);
  issues.sort(
    (a, b) =>
        '${a['path']}/${a['code']}'.compareTo('${b['path']}/${b['code']}'),
  );
  final now = DateTime.now();
  final date =
      '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  final directory = Directory('${root.path}/_system/health');
  await directory.create(recursive: true);
  final report = File('${directory.path}/$date.json');
  final temporary = File('${report.path}.tmp');
  await temporary.writeAsString(
    '${const JsonEncoder.withIndent('  ').convert({'date': date, 'scanned': scanned, 'typstCompile': typstCompile, 'issues': issues})}\n',
    flush: true,
  );
  await temporary.rename(report.path);
  return report.readAsString();
}

bool _isAutoEntitiesMarkerLine(String line) {
  final content = line.trimLeft();
  if (RegExp(r'^(?:[-+*]|\d+[.)])\s+').hasMatch(content)) return false;
  return content.startsWith('// tylog:auto-entities');
}

const _healthTypstBatchSize = 20;

Future<Map<String, Object>> _checkTypstBatch(
  Directory root,
  Map<String, File> noteFiles,
  List<Map<String, String>> issues,
) async {
  final paths = noteFiles.keys.toList()..sort();
  if (paths.isEmpty) {
    return const {'checked': 0, 'batchSize': _healthTypstBatchSize};
  }
  final cursor = File('${root.path}/_system/health/typst-cursor.json');
  String? lastPath;
  try {
    final saved = jsonDecode(await cursor.readAsString());
    if (saved is Map && saved['lastPath'] is String) {
      lastPath = saved['lastPath'] as String;
    }
  } on FileSystemException {
    // Start at the beginning on the first run.
  } on FormatException {
    // A damaged cursor is disposable; the report remains authoritative.
  }
  var start = lastPath == null
      ? 0
      : paths.indexWhere((path) => path.compareTo(lastPath!) > 0);
  if (start < 0) start = 0;
  final batch = paths.skip(start).take(_healthTypstBatchSize).toList();
  final output = await Directory.systemTemp.createTemp('tylog-health-typst-');
  var checked = 0;
  try {
    for (var i = 0; i < batch.length; i++) {
      final path = batch[i];
      try {
        final result = await Process.run('typst', [
          'compile',
          '--root',
          root.path,
          '--diagnostic-format',
          'short',
          noteFiles[path]!.path,
          '${output.path}/$i.pdf',
        ], workingDirectory: root.path);
        checked++;
        if (result.exitCode != 0) {
          issues.add({'path': path, 'code': 'typst-compile-error'});
        }
      } on ProcessException {
        return {
          'checked': checked,
          'batchSize': _healthTypstBatchSize,
          'available': false,
        };
      }
    }
  } finally {
    await output.delete(recursive: true);
  }
  final next = batch.last;
  await cursor.parent.create(recursive: true);
  await cursor.writeAsString(jsonEncode({'lastPath': next}), flush: true);
  return {
    'checked': checked,
    'batchSize': _healthTypstBatchSize,
    'available': true,
  };
}

Future<int> _migrateMentions(List<String> args) async {
  final apply = args.remove('--apply');
  if (args.length != 1 || args.single.startsWith('--')) {
    throw _UsageException('migrate-mentions requires <vault> [--apply]');
  }
  final root = Directory(args.single).absolute;
  final storage = LocalVaultStorage(root);
  if ((await inspectVaultStorage(storage)).kind !=
      VaultStorageKind.validVault) {
    throw StateError('TyLog vault marker is missing or invalid');
  }
  final files = await root
      .list(recursive: true, followLinks: false)
      .where((e) {
        if (e is! File || !e.path.endsWith('.typ')) return false;
        final relative = e.path.substring(root.path.length + 1);
        return !relative
            .split(Platform.pathSeparator)
            .any((part) => part.startsWith('_system') || part.startsWith('.'));
      })
      .cast<File>()
      .toList();
  files.sort((a, b) => a.path.compareTo(b.path));
  final stamp = DateTime.now().toIso8601String().replaceAll(
    RegExp(r'[^0-9]'),
    '',
  );
  for (final file in files) {
    final relative = file.path.substring(root.path.length + 1);
    final source = await file.readAsString();
    final marker = RegExp(
      r'^// tylog:auto-entities\r?\n== Mentions\r?\n',
      multiLine: true,
    ).firstMatch(source);
    if (marker == null) continue;
    final lines = source.substring(marker.end).split('\n');
    final entries = <String>[];
    var count = 0;
    while (count < lines.length &&
        (lines[count].trim().isEmpty ||
            RegExp(
              r'^\s*(?:[-+*]\s*)?#tylog\.(?:ref-note|tag)\(',
            ).hasMatch(lines[count]))) {
      entries.add(lines[count++]);
    }
    final tail = lines.skip(count).join('\n');
    var body = source.substring(0, marker.start);
    final added = <String>[],
        dropped = <String>[],
        moved = <String>[],
        remaining = <String>[];
    for (final line in entries) {
      final link = RegExp(
        r'^\s*[-+*]\s*#tylog\.ref-note\("([^"\\]+)"\)\[([^\[\]]+)\]\s*\r?$',
      ).firstMatch(line);
      final tagLine = RegExp(
        r'^\s*(?:#tylog\.tag\("[^"\\]+"\)\s*)+\r?$',
      ).hasMatch(line);
      if (link != null) {
        final id = link[1]!, surface = link[2]!;
        if (scanNote(relative, body).outgoingLinks.contains(id)) {
          dropped.add(id);
          continue;
        }
        final target = NoteRef(
          id: id,
          path: '',
          title: surface,
          outgoingLinks: const [],
        );
        var next = body;
        for (var i = 0; i < body.split('\n').length && next == body; i++) {
          next = linkMentionInline(
            body,
            EnrichMention(surface: surface, type: '', line: i + 1),
            target,
          );
        }
        if (next != body) {
          body = next;
          added.add(id);
          continue;
        }
      } else if (tagLine) {
        final tags = RegExp(
          r'#tylog\.tag\("([^"\\]+)"\)',
        ).allMatches(line).map((m) => m[1]!).toList();
        final next = addEnrichHeaderTags(body, relative, tags);
        if (next != body ||
            tags.every((t) => scanNote(relative, body).tags.contains(t))) {
          body = next;
          moved.addAll(tags);
          continue;
        }
      }
      if (line.trim().isNotEmpty) remaining.add(line);
    }
    final result =
        '$body${remaining.isEmpty ? '' : '${source.substring(marker.start, marker.end)}${remaining.join('\n')}\n'}$tail';
    stdout.writeln(
      '$relative | links to add inline: ${added.join(', ')} | links dropped as already inline: ${dropped.join(', ')} | tags moved to header: ${moved.join(', ')} | retained: ${remaining.join('; ')}',
    );
    if (apply && result != source) {
      final backup = File(
        '${root.path}/_system/backups/mentions-$stamp/$relative',
      );
      await backup.parent.create(recursive: true);
      if (await backup.exists()) {
        throw StateError('Backup already exists: ${backup.path}');
      }
      if (await file.readAsString() != source) {
        throw StateError('File changed during migration: $relative');
      }
      await backup.writeAsBytes(utf8.encode(source), flush: true);
      if (await file.readAsString() != source) {
        throw StateError('File changed during migration: $relative');
      }
      await file.writeAsString(result, flush: true);
    }
  }
  return 0;
}

Future<int> _importContacts(List<String> args) async {
  final write = args.remove('--write');
  final options = <String, String>{};
  for (var i = 0; i < args.length; i += 2) {
    if (!const {'--vault', '--file'}.contains(args[i]) ||
        i + 1 >= args.length ||
        args[i + 1].startsWith('--') ||
        options.containsKey(args[i])) {
      throw _UsageException('Invalid import-contacts option: ${args[i]}');
    }
    options[args[i]] = args[i + 1];
  }
  if (options.length != 2) {
    throw _UsageException('import-contacts requires --vault and --file');
  }
  final vault = Directory(options['--vault']!).absolute;
  if ((await inspectVaultStorage(LocalVaultStorage(vault))).kind !=
      VaultStorageKind.validVault) {
    throw StateError('TyLog vault marker is missing or invalid');
  }
  final result = await importContacts(
    vault,
    File(options['--file']!),
    write: write,
  );
  stdout.writeln(
    '${write ? 'Created' : 'Would create'} ${result.created}; skipped ${result.skipped}',
  );
  return 0;
}

Future<int> _evalLinks(List<String> args) async {
  final options = <String, String>{};
  for (var i = 0; i < args.length; i += 2) {
    if (!const {'--vault', '--gold', '--sample', '--out'}.contains(args[i]) ||
        i + 1 >= args.length ||
        args[i + 1].startsWith('--') ||
        options.containsKey(args[i])) {
      throw _UsageException('Invalid eval-links option: ${args[i]}');
    }
    options[args[i]] = args[i + 1];
  }
  final sample = options['--sample'];
  final count = sample == null ? null : int.tryParse(sample);
  if (options['--vault'] == null ||
      (sample == null &&
          (options['--gold'] == null || options['--out'] != null)) ||
      (sample != null &&
          (count == null || count <= 0 || options['--out'] == null))) {
    throw _UsageException(
      'eval-links requires --vault and --gold, or --sample N --out',
    );
  }
  final storage = LocalVaultStorage(Directory(options['--vault']!).absolute);
  final index = await loadVaultIndex(storage);
  if (index == null) {
    throw StateError('No readable vault index; run tylog index first');
  }
  if (count != null) {
    final rows = await sampleLinks(storage, index, count);
    await File(
      options['--out']!,
    ).writeAsString('${rows.map(jsonEncode).join('\n')}\n');
    stdout.writeln('Wrote ${rows.length} mentions to ${options['--out']}');
  } else {
    stdout.write(
      await evaluateLinks(
        storage,
        index,
        await File(options['--gold']!).readAsString(),
      ),
    );
  }
  return 0;
}

/// Checks a `.tylogpack` against docs/modules/PACK-SPEC.md: manifest, hashes,
/// paths, and that notes import nothing but the tylog helper (the in-app
/// compile has no other files).
Future<int> _packValidate(List<String> args) async {
  if (args.length != 1) throw _UsageException('pack-validate takes one pack');
  final zip = ZipDecoder().decodeBytes(await File(args.single).readAsBytes());
  final entries = {
    for (final f in zip.files)
      if (f.isFile) f.name: Uint8List.fromList(f.content),
  };
  final ModulePack pack;
  try {
    pack = ModulePack.parse(entries);
  } on FormatException catch (error) {
    stderr.writeln('invalid: ${error.message}');
    return 1;
  }
  var problems = 0;
  for (final entry in pack.files.entries) {
    if (!entry.key.endsWith('.typ')) continue;
    for (final line in utf8.decode(entry.value).split('\n')) {
      final m = RegExp(r'^\s*#import\s+"([^"]+)"').firstMatch(line);
      if (m != null && m[1] != '/_system/tylog.typ') {
        stderr.writeln('${entry.key}: unsupported import ${m[1]}');
        problems++;
      }
    }
  }
  stdout.writeln(
    '${pack.id} ${pack.version}: ${pack.files.length} files, $problems problems',
  );
  return problems == 0 ? 0 : 1;
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
  // The same routine the app's worker and the background service run: scan,
  // write the index, publish this machine's donor, rebuild search, sweep the
  // leftovers. Indexing on a desktop is minutes of Typst compiles that every
  // other device would otherwise repeat for itself, so the donor is the whole
  // point of running it here — and until this shared it, the CLI published one
  // but never *consumed* the peers', and never swept.
  final maintenance = VaultMaintenance(storage, publishDonor: true);
  final deviceId = await _cliDeviceId(storage);
  late final VaultIndex index;
  await for (final event in maintenance.run(
    inspector: CliTypstInspector(root),
    force: force,
    deviceId: deviceId,
    // Nothing here renders a problems report; `tylog doctor` is the command
    // that does, and it prints them.
    validate: false,
    flushSearchOnFinish: true,
  )) {
    switch (event) {
      case MaintenanceIndexed(index: final built):
        index = built;
      case MaintenanceSwept(:final deleted):
        if (deleted > 0) stdout.writeln('Swept $deleted leftover file(s)');
      default:
        break;
    }
  }
  stdout.writeln(
    'Indexed ${index.notes.length} notes and ${index.tasks.length} tasks '
    '(${index.problems.length} warnings); published donor $deviceId',
  );
  for (final problem in index.problems) {
    stderr.writeln(
      '${problem.severity.name}: ${problem.subject}: ${problem.message}',
    );
  }
  return 0;
}

/// A stable id for this machine's donor, kept in `.tylog/` (device-local, and
/// outside the sync allowlist) so repeated runs republish one file instead of
/// littering `_system/index/` with a new donor per invocation.
Future<int> _cluster(List<String> args) async {
  if (args.length != 1 || args.single.startsWith('--')) {
    throw _UsageException('cluster requires <vault>');
  }
  final root = Directory(args.single).absolute;
  final storage = LocalVaultStorage(root);
  await _openVault(storage);
  final stateFile = File(
    '${Platform.environment['HOME'] ?? Directory.current.path}/.tylog-cluster-state.json',
  );
  Map state = {};
  try {
    state = jsonDecode(await stateFile.readAsString()) as Map;
  } on Object {
    // No run history yet.
  }
  final requestFile = File('${root.path}/_system/clusters/run-request.json');
  Object? requested;
  if (await requestFile.exists()) {
    try {
      final request = jsonDecode(await requestFile.readAsString());
      if (request is Map) requested = request['requested_at'];
    } on FormatException {
      // Ignore malformed optional request; the nightly run still proceeds.
    }
  }
  final nowLocal = DateTime.now();
  final date =
      '${nowLocal.year.toString().padLeft(4, '0')}-${nowLocal.month.toString().padLeft(2, '0')}-${nowLocal.day.toString().padLeft(2, '0')}';
  final scheduledRun =
      // Once per day after 03:00: the agent wakes every 10 minutes, so an
      // exact-minute check would almost never fire.
      nowLocal.hour >= 3 && state['last_scheduled_date'] != date;
  final requestedRun =
      requested != null && requested != state['last_run_request'];
  if (!scheduledRun && !requestedRun) return 0;
  final maintenance = VaultMaintenance(storage, publishDonor: true);
  final deviceId = await _cliDeviceId(storage);
  late final VaultIndex index;
  await for (final event in maintenance.run(
    inspector: CliTypstInspector(root),
    deviceId: deviceId,
    validate: false,
    flushSearchOnFinish: true,
  )) {
    if (event case MaintenanceIndexed(index: final built)) index = built;
  }
  final next = <String, Set<String>>{};
  for (final entry in computeCommunities(index).tagToCluster.entries) {
    next.putIfAbsent(entry.value, () => <String>{}).add(entry.key);
  }
  final snapshotFile = File('${root.path}/_system/clusters/snapshot.json');
  Map<String, Set<String>> previous = {};
  try {
    final decoded = ClusterSnapshot.fromJson(
      jsonDecode(await snapshotFile.readAsString()) as Map,
    );
    previous = decoded.clusters;
  } on FileSystemException {
    /* First run. */
  } on FormatException {
    /* Rebuild malformed snapshots. */
  }
  final match = matchClusters(previous, next);
  final decisions = await _clusterChangeDecisions(root);
  final clusters = <String, Set<String>>{
    for (final entry in next.entries)
      match.stableLabel[entry.key] ?? entry.key: entry.value,
  };
  for (final change in match.changes) {
    if (!const {'rename', 'merge', 'split'}.contains(change.kind)) continue;
    final id = _clusterChangeId(change);
    if (decisions.accepted.contains(id)) {
      // Accepted vocabulary changes take the labels and membership from `to`.
      for (final label in change.from) {
        clusters.remove(label);
      }
      for (final label in change.to) {
        clusters.remove(match.stableLabel[label] ?? label);
        if (next.containsKey(label)) clusters[label] = next[label]!;
      }
    } else {
      // Until accepted (including rejected changes), keep the old vocabulary.
      for (final label in change.to) {
        clusters.remove(match.stableLabel[label] ?? label);
        clusters.remove(label);
      }
      for (final label in change.from) {
        if (previous.containsKey(label)) clusters[label] = previous[label]!;
      }
    }
  }
  final now = DateTime.now().toUtc().toIso8601String();
  await _atomicJson(
    snapshotFile,
    ClusterSnapshot(generatedAt: now, clusters: clusters).toJson(),
  );
  final proposals = [
    for (final change in match.changes)
      if (!decisions.rejected.contains(_clusterChangeId(change)) &&
          !decisions.accepted.contains(_clusterChangeId(change)))
        {
          'id': _clusterChangeId(change),
          'kind': change.kind,
          'from': change.from,
          'to': change.to,
        },
  ];
  if (requestedRun) state['last_run_request'] = requested;
  if (scheduledRun) state['last_scheduled_date'] = date;
  await stateFile.parent.create(recursive: true);
  final stateTmp = File('${stateFile.path}.tmp');
  await stateTmp.writeAsString(jsonEncode(state), flush: true);
  await stateTmp.rename(stateFile.path);
  await _atomicJson(File('${root.path}/_system/clusters/proposals.json'), {
    'schema': 1,
    'generated_at': now,
    'changes': proposals,
  });
  stdout.writeln(
    'Wrote ${clusters.length} clusters and ${proposals.length} proposal(s)',
  );
  return 0;
}

String _clusterChangeId(ClusterChange change) =>
    '${change.kind}:${change.from.join('+')}->${change.to.join('+')}';

class _ClusterChangeDecisions {
  const _ClusterChangeDecisions(this.accepted, this.rejected);
  final Set<String> accepted;
  final Set<String> rejected;
}

Future<_ClusterChangeDecisions> _clusterChangeDecisions(Directory root) async {
  final accepted = <String>{};
  final rejected = <String>{};
  final directory = Directory('${root.path}/_system/decisions');
  if (!await directory.exists()) {
    return _ClusterChangeDecisions(accepted, rejected);
  }
  await for (final entry in directory.list()) {
    if (entry is! File || !entry.path.endsWith('.jsonl')) continue;
    for (final line in await entry.readAsLines()) {
      try {
        final row = jsonDecode(line);
        if (row is Map &&
            row['source'] == 'clusters' &&
            row['target'] is String) {
          if (row['action'] == 'accepted') {
            accepted.add(row['target'] as String);
          }
          if (row['action'] == 'rejected') {
            rejected.add(row['target'] as String);
          }
        }
      } on FormatException {
        /* Ignore a partial ledger line. */
      }
    }
  }
  return _ClusterChangeDecisions(accepted, rejected);
}

Future<void> _atomicJson(File file, Object value) async {
  await file.parent.create(recursive: true);
  final temporary = File('${file.path}.tmp');
  await temporary.writeAsString(
    '${const JsonEncoder.withIndent('  ').convert(value)}\n',
    flush: true,
  );
  await temporary.rename(file.path);
}

Future<String> _cliDeviceId(VaultStorage storage) async {
  const path = '.tylog/cli-device-id';
  try {
    if (await storage.exists(path)) {
      final existing = (await storage.readText(path)).trim();
      if (existing.isNotEmpty) return existing;
    }
  } catch (_) {
    // Fall through and mint a new one.
  }
  // Host-derived, so a machine keeps its identity even if `.tylog/` is wiped.
  final seed = '${Platform.localHostname}|${Platform.operatingSystem}';
  final id =
      'cli-${sha256.convert(utf8.encode(seed)).toString().substring(0, 12)}';
  try {
    await storage.createDirectory('.tylog');
    await storage.writeText(path, id);
  } catch (_) {
    // Not being able to remember it only costs a re-derive next run.
  }
  return id;
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
  // With an inspector, like index and doctor. Without one every note falls to
  // the source parser, and this command decides which files to *delete* from
  // `id` and `import_sha256` — reading those from a fallback parse and then
  // acting on it under --apply is the one place a wrong id is destructive.
  final index = await scanVaultStorage(
    storage,
    inspector: CliTypstInspector(Directory(args.single).absolute),
    force: true,
  );
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
  if (apply && (deletions > 0 || merges > 0 || reassigned > 0)) {
    // The index and this machine's donor now describe files that are gone or
    // ids that moved — and the donor *syncs*, so leaving them stale propagates
    // the lie to every phone. Every other mutating path in the app reindexes
    // after writing; this one returned straight to the shell.
    await _republishIndexArtifacts(storage, Directory(args.single).absolute);
  }
  return 0;
}

/// Rebuilds and republishes everything derived from the notes on disk.
///
/// Shared with [_index]'s tail so a command that mutates notes cannot forget
/// half of it: the index, the donor peers read, and the search index.
Future<void> _republishIndexArtifacts(
  LocalVaultStorage storage,
  Directory root,
) async {
  final deviceId = await _cliDeviceId(storage);
  var notes = 0;
  await for (final event in VaultMaintenance(storage, publishDonor: true).run(
    inspector: CliTypstInspector(root),
    force: true,
    deviceId: deviceId,
    validate: false,
  )) {
    if (event case MaintenanceIndexed(:final index)) notes = index.notes.length;
  }
  stdout.writeln('Reindexed $notes notes; republished donor $deviceId');
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
  tylog mcp <vault>
  tylog init [vault=.]
  tylog import-contacts --vault <dir> --file <contacts.vcf|contacts.csv> [--write]
  tylog index [vault=.] [--force]
  tylog cluster <vault>
  tylog doctor [vault=.]
  tylog vault-health <vault>
  tylog dedupe <vault> [--apply]
  tylog migrate-mentions <vault> [--apply]
  tylog export <file.typ> [output.pdf]
  tylog pack-validate <file.tylogpack>
  tylog eval-links --vault <dir> --gold <file.jsonl>
  tylog eval-links --vault <dir> --sample N --out <file.jsonl>''';
