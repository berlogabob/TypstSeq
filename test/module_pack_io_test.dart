import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/module_pack_io.dart';
import 'package:tylog_core/tylog_core.dart';

// Set TYLOG_PORTUGUESE_PACK=/path/to/pt-pt-a2b1.tylogpack to run.
void main() {
  final packPath = Platform.environment['TYLOG_PORTUGUESE_PACK'];
  test(
    'real course pack installs and scans back with scheduled tasks and audio',
    () async {
      final pack = await readModulePack(File(packPath!));
      final dir = await Directory.systemTemp.createTemp('pack_vault_');
      addTearDown(() => dir.delete(recursive: true));
      final storage = LocalVaultStorage(dir);
      final r = await installModule(storage, pack, DateTime(2026, 11, 2));
      expect(r.skipped, isEmpty);

      final index = await scanVaultStorage(storage);
      final lessons = index.notes.where((n) => n.id.startsWith(pack.id));
      expect(lessons, hasLength(72));
      final due = index.tasks.map((t) => t.due).toSet();
      expect(index.tasks, hasLength(72));
      // Lesson 1 on the start date, lesson 7 skips the rest day (7th).
      expect(
        index.tasks.firstWhere((t) => t.id.endsWith('0001-task')).due,
        '2026-11-02',
      );
      expect(
        index.tasks.firstWhere((t) => t.id.endsWith('0007-task')).due,
        '2026-11-09',
      );
      expect(due.length, 72);
      final audio = lessons
          .expand((n) => n.attachments)
          .where((a) => a.kind == 'audio');
      expect(audio, isNotEmpty);
      for (final a in audio) {
        expect(await storage.exists(a.path), isTrue, reason: a.path);
      }
    },
    skip: packPath == null ? 'TYLOG_PORTUGUESE_PACK not set' : false,
    timeout: const Timeout(Duration(minutes: 10)),
  );
}
