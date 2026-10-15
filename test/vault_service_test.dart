import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/vault_service.dart';
import 'package:tylog_core/storage.dart';

void main() {
  late Directory directory;
  late LocalVaultStorage storage;
  final now = DateTime.utc(2026, 10, 16);

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('tylog_service_');
    storage = LocalVaultStorage(directory);
  });
  tearDown(() => directory.delete(recursive: true));

  for (final event in ['completed', 'no-change-shortcut']) {
    test('$event skips background sync for less than five minutes', () async {
      await storage.writeText(
        '.tylog/sync_trace.jsonl',
        '${jsonEncode({'event': event, 'trigger': 'poll', 'timestamp': now.toIso8601String()})}\n',
      );
      expect(
        await backgroundSyncRecentlyCompleted(
          storage,
          now: now.add(const Duration(minutes: 4, seconds: 59)),
        ),
        isTrue,
      );
      expect(
        await backgroundSyncRecentlyCompleted(
          storage,
          now: now.add(const Duration(minutes: 5)),
        ),
        isFalse,
      );
    });
  }

  test('checkpoints and failed runs do not count as successful syncs', () async {
    await storage.writeText('.tylog/sync_state.json', '{"cursors":{}}');
    expect(await backgroundSyncRecentlyCompleted(storage, now: now), isFalse);
    await storage.writeText(
      '.tylog/sync_trace.jsonl',
      '${jsonEncode({'event': 'failed', 'timestamp': now.toIso8601String()})}\n',
    );
    expect(await backgroundSyncRecentlyCompleted(storage, now: now), isFalse);
  });

  test('malformed trace lines do not hide a recent success', () async {
    await storage.writeText(
      '.tylog/sync_trace.jsonl',
      '${jsonEncode({'event': 'completed', 'timestamp': now.toIso8601String()})}\n{"event":"completed"}\nbroken\n',
    );
    expect(await backgroundSyncRecentlyCompleted(storage, now: now), isTrue);
  });
}
