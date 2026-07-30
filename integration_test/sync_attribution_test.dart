import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tylog/nextcloud_sync.dart';

/// Phase 2, step one: what actually blocks the root isolate during a sync?
///
/// Phase 1 taught the lesson the hard way — the synthetic index fixture
/// understated the real vault by ~60x — so this measures before anything is
/// designed. It prices the two things `NextcloudSync` does on the calling isolate
/// that scale with vault size rather than with the network:
///
///   * the per-10-file checkpoint, which copies the whole cursor map and
///     `jsonEncode`s it (`_saveSyncState`), and
///   * the end-of-run trace flush, which reads the entire `sync_trace.jsonl`
///     back and rewrites it (`_appendTrace`).
///
/// Sized from the real device: 2061 synced paths, a 607 KB `sync_state.json` and
/// a 396 KB `sync_trace.jsonl`.
///
/// Prints a breakdown; the numbers are the deliverable, not a pass/fail.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const paths = 2061;
  const checkpointEvery = 10;

  test('cost of sync checkpointing at real-vault scale', () async {
    // A cursor per synced path, shaped like the real thing: sha256 hex and an
    // etag are what make this file 600 KB rather than 60.
    final cursors = <String, SyncCursor>{
      for (var i = 0; i < paths; i++)
        'articles/Some Reasonably Long Article Title Number $i.typ': SyncCursor(
          localMillis: 1785407955000 + i,
          localSize: 4096 + i,
          remoteMillis: 1785396828000 + i,
          localSha256: '${i.toRadixString(16).padLeft(8, '0')}'
              'a3f9c1d2e4b5768900112233445566778899aabbccddeeff00112233445566',
          remoteEtag: '${i.toRadixString(16).padLeft(8, '0')}d549ce32fd50efcc',
        ),
    };

    // What one checkpoint costs, exactly as the sync loop does it.
    String? encoded;
    final one = Stopwatch()..start();
    final snapshot = Map<String, SyncCursor>.of(cursors);
    encoded = jsonEncode({
      'schema': 2,
      'remoteKey': 'https://example/remote.php/dav/files/alice/TyLogVault',
      'rootEtag': 'abc123',
      'cursors': {for (final e in snapshot.entries) e.key: e.value.toJson()},
    });
    one.stop();

    final checkpoints = paths ~/ checkpointEvery;
    final total = Stopwatch()..start();
    for (var i = 0; i < checkpoints; i++) {
      final snap = Map<String, SyncCursor>.of(cursors);
      jsonEncode({
        'schema': 2,
        'remoteKey': 'https://example/remote.php/dav/files/alice/TyLogVault',
        'rootEtag': 'abc123',
        'cursors': {for (final e in snap.entries) e.key: e.value.toJson()},
      });
    }
    total.stop();

    // The trace flush: read the whole file back, then write it plus the new
    // events. Once per run, but the file is ~400 KB on the real device.
    final traceDir = await Directory.systemTemp.createTemp('tylog_trace_');
    addTearDown(() => traceDir.delete(recursive: true));
    final traceFile = File('${traceDir.path}/sync_trace.jsonl');
    final line = '${jsonEncode({
          'timestamp': '2026-07-30T10:40:10.750070Z',
          'runId': 'abcdef0123456789',
          'event': 'sync-file',
          'path': 'articles/Some Reasonably Long Article Title.typ',
          'decision': 'upload',
        })}\n';
    await traceFile.writeAsString(line * 1200); // ~400 KB, as on the device
    final traceBytes = await traceFile.length();

    final trace = Stopwatch()..start();
    final existing = await traceFile.readAsBytes();
    await traceFile.writeAsBytes([
      ...existing,
      ...utf8.encode(line * 20),
    ]);
    trace.stop();

    // ignore: avoid_print
    print(
      'SYNC-ATTRIBUTION paths=$paths\n'
      '  sync_state.json encoded size: ${(encoded.length / 1024).round()} KB\n'
      '  one checkpoint (copy+encode): ${one.elapsedMilliseconds} ms\n'
      '  $checkpoints checkpoints/run:  ${total.elapsedMilliseconds} ms total\n'
      '  trace flush (${(traceBytes / 1024).round()} KB read+write): '
      '${trace.elapsedMilliseconds} ms',
    );

    expect(encoded.length, greaterThan(0));
  });
}
