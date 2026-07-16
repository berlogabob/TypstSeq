// Repro harness for the on-device scan hang (audit 2026-07-16 §3-L1).
// Usage: dart run tool/scan_repro.dart <vault-dir>
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:tylog_core/tylog_core.dart';

Future<void> main(List<String> args) async {
  final root = Directory(args.first);
  var last = DateTime.now();
  String? current;
  final ticker = Timer.periodic(const Duration(seconds: 5), (_) {
    final silent = DateTime.now().difference(last);
    stderr.writeln('[stuck ${silent.inSeconds}s] current=$current');
  });
  final watch = Stopwatch()..start();
  final index = await scanVaultStorage(
    _TracingStorage(LocalVaultStorage(root), (path) {
      current = path;
      last = DateTime.now();
    }),
    onProgress: (complete, total) {
      if (complete % 100 == 0 || complete == total) {
        stdout.writeln('progress $complete/$total ${watch.elapsed}');
      }
    },
  );
  ticker.cancel();
  stdout.writeln(
    'DONE notes=${index.notes.length} tasks=${index.tasks.length} '
    'problems=${index.problems.length} in ${watch.elapsed}',
  );
}

class _TracingStorage extends VaultStorage {
  _TracingStorage(this.inner, this.onRead);
  final VaultStorage inner;
  final void Function(String path) onRead;

  @override
  Future<List<VaultStorageEntry>> list({
    String path = '',
    bool recursive = false,
  }) => inner.list(path: path, recursive: recursive);

  @override
  Future<Uint8List> readBytes(String path) {
    onRead(path);
    return inner.readBytes(path);
  }

  @override
  Future<VaultStorageEntry?> stat(String path) => inner.stat(path);

  @override
  Future<bool> exists(String path) => inner.exists(path);

  @override
  Future<void> createDirectory(String path) => inner.createDirectory(path);

  @override
  Future<void> writeBytes(String path, List<int> bytes) =>
      inner.writeBytes(path, bytes);

  @override
  Future<void> delete(String path) => inner.delete(path);

  @override
  Future<String> hash(String path) => inner.hash(path);
}
