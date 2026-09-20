import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tylog/database/tylog_database.dart';
import 'package:tylog/vault_registry.dart';
import 'package:tylog/task_scheduler.dart';
import 'package:tylog/vault.dart';
import 'package:tylog/workspace_controller.dart';

int _p95(List<int> values) {
  final sorted = [...values]..sort();
  return sorted[((sorted.length * 95 + 99) ~/ 100) - 1];
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('P12e Android editor save path acceptance', (_) async {
    final root = await Directory.systemTemp.createTemp('tylog-p12-editor-');
    final database = TyLogDatabase(NativeDatabase.memory());
    final controller = WorkspaceController(
      taskScheduler: TaskScheduler(),
      database: Future.value(database),
      useForegroundService: false,
    );
    addTearDown(() async {
      controller.dispose();
      await database.close();
      await root.delete(recursive: true);
    });

    final vault = Vault(root);
    controller.vault = vault;
    controller.entry = const VaultEntry(
      id: 'p12-editor',
      name: 'P12',
      path: '/p12',
    );
    final path = 'notes/p12.typ';
    final source = '#show: tylog.note.with(id: "p12", title: "P12")\nseed';
    controller.note = path;
    controller.source = source;
    final saves = <int>[];
    for (var i = 0; i < 100; i++) {
      controller.edit('$source\n#let p12 = $i\n');
      final watch = Stopwatch()..start();
      expect(await controller.save(syncAfter: false), isTrue);
      saves.add(watch.elapsedMilliseconds);
    }
    expect(await controller.vault!.storage.exists(path), isTrue);
    final p95 = _p95(saves);
    expect(p95, lessThanOrEqualTo(150));
    saves.sort();
    final opens = <int>[];
    for (var i = 0; i < 100; i++) {
      final watch = Stopwatch()..start();
      final snapshot = await controller.readNoteSnapshot(path);
      expect(controller.adoptNoteRead(path, snapshot), isTrue);
      opens.add(watch.elapsedMilliseconds);
    }
    final openP95 = _p95(opens);
    expect(openP95, lessThanOrEqualTo(150));
    opens.sort();
    // ignore: avoid_print
    print(
      'P12e android editor_save_ms p50=${saves[49]} p95=$p95 '
      'max=${saves.last}; editor_open_ms p50=${opens[49]} '
      'p95=$openP95 max=${opens.last}; samples=100/100',
    );
  });
}
