import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/scanner.dart';
import 'package:tylog/search_index.dart';
import 'package:tylog/vault_storage.dart';

void main() {
  test(
    'buildStorage parallelizes cold reads instead of awaiting them serially',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'tylog_saf_latency_',
      );
      addTearDown(() => dir.delete(recursive: true));
      final notesDir = await Directory('${dir.path}/notes').create();
      const noteCount = 1500;
      for (var i = 0; i < noteCount; i++) {
        await File('${notesDir.path}/n$i.typ').writeAsString(
          '#show: tylog.note.with(id: "n$i", title: "Note $i", tags: ("pkms",))\n'
          'Knowledge body $i',
        );
      }

      // Build the vault index with plain (fast) local storage; only the
      // search-index build below is timed against simulated per-file
      // latency, mirroring a slow Android SAF `readBytes` round trip.
      final index = await scanVault(dir, force: true);
      expect(index.notes, hasLength(noteCount));

      final latencyStorage = _LatencyStorage(dir);
      final stopwatch = Stopwatch()..start();
      final search = await PkmsSearchIndex.buildStorage(
        latencyStorage,
        index,
      );
      stopwatch.stop();

      // Serial reads at 15ms each would take ~22.5s; bounded-concurrency
      // parallel reads must finish well under that.
      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 5)));
      expect(
        search.search('', limit: noteCount + 10),
        hasLength(noteCount),
      );
    },
  );
}

class _LatencyStorage extends LocalVaultStorage {
  _LatencyStorage(super.root);

  @override
  Future<Uint8List> readBytes(String path) async {
    await Future.delayed(const Duration(milliseconds: 15));
    return super.readBytes(path);
  }
}
