// Measure the retained RSS of the search index without writing to the vault.
// Usage: dart run tool/search_index_memory.dart <vault-dir>
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:tylog_core/search_index.dart';
import 'package:tylog_core/scanner.dart';
import 'package:tylog_core/storage.dart';

Future<void> main(List<String> args) async {
  if (args.length == 2 && args.first == '--load') {
    final file = File(args[1]).absolute;
    final load = await _measureLoad(file.parent, file.uri.pathSegments.last);
    stdout.writeln('load $load');
    return;
  }
  if (args.length != 1) {
    stderr.writeln('usage: dart run tool/search_index_memory.dart <vault-dir>');
    exitCode = 64;
    return;
  }

  final vaultRoot = Directory(args.single).absolute;
  final tempRoot = await Directory.systemTemp.createTemp(
    'tylog_search_memory_',
  );
  try {
    final indexPath = '${tempRoot.path}/search-index.json.gz';
    final build = await _measureBuild(vaultRoot, tempRoot);
    stdout.writeln('build $build');
    final childArgs = [
      if (Platform.script.path.endsWith('.dart')) Platform.script.toFilePath(),
      '--load',
      indexPath,
    ];
    final child = await Process.run(Platform.resolvedExecutable, [
      ...childArgs,
    ], workingDirectory: Directory.current.path);
    stdout.write(child.stdout);
    stderr.write(child.stderr);
    if (child.exitCode != 0) exitCode = child.exitCode;
  } finally {
    await tempRoot.delete(recursive: true);
  }
}

Future<Map<String, Object>> _measureBuild(
  Directory vaultRoot,
  Directory tempRoot,
) async {
  final storage = _ReadOnlyStorage(LocalVaultStorage(vaultRoot));
  final vault = await scanVaultStorage(storage);
  await _settle();
  final before = ProcessInfo.currentRss;
  final index = await PkmsSearchIndex.buildStorage(storage, vault);
  await _settle();
  final after = ProcessInfo.currentRss;
  await index.saveStorage(LocalVaultStorage(tempRoot), 'search-index.json.gz');
  return {
    'notes': index.debugStats['notes']!,
    'terms': index.debugStats['vocabulary']!,
    'postings': index.debugStats['postings']!,
    'rssDeltaBytes': after - before,
  };
}

Future<Map<String, Object>> _measureLoad(
  Directory tempRoot,
  String fileName,
) async {
  final storage = LocalVaultStorage(tempRoot);
  await _settle();
  final before = ProcessInfo.currentRss;
  final index = await PkmsSearchIndex.loadStorage(storage, fileName);
  await _settle();
  final after = ProcessInfo.currentRss;
  return {
    'notes': index.debugStats['notes']!,
    'terms': index.debugStats['vocabulary']!,
    'postings': index.debugStats['postings']!,
    'rssDeltaBytes': after - before,
  };
}

Future<void> _settle() async {
  // The standalone Dart VM has no public synchronous GC API. Allocation
  // pressure followed by an event-loop turn reliably collects short-lived
  // scanner/JSON objects on the benchmark VM; RSS is intentionally reported
  // as a delta, so allocator high-water marks cancel out.
  final pressure = <Uint8List>[];
  for (var i = 0; i < 8; i++) {
    pressure.add(Uint8List(8 * 1024 * 1024));
  }
  await Future<void>.delayed(Duration.zero);
  pressure.clear();
  await Future<void>.delayed(const Duration(milliseconds: 50));
}

class _ReadOnlyStorage extends VaultStorage {
  _ReadOnlyStorage(this.inner);
  final VaultStorage inner;

  @override
  Future<bool> exists(String path) => inner.exists(path);

  @override
  Future<void> createDirectory(String path) =>
      Future.error(StateError('benchmark storage is read-only'));

  @override
  Future<List<VaultStorageEntry>> list({
    String path = '',
    bool recursive = false,
  }) => inner.list(path: path, recursive: recursive);

  @override
  Future<VaultStorageEntry?> stat(String path) => inner.stat(path);

  @override
  Future<Uint8List> readBytes(String path) => inner.readBytes(path);

  @override
  Future<void> writeBytes(String path, List<int> bytes) =>
      Future.error(StateError('benchmark storage is read-only'));

  @override
  Future<void> delete(String path) =>
      Future.error(StateError('benchmark storage is read-only'));

  @override
  Future<String> hash(String path) => inner.hash(path);
}
