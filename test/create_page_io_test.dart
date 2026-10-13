import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/database/tylog_database.dart';
import 'package:tylog/scanner.dart';
import 'package:tylog/task_scheduler.dart';
import 'package:tylog/vault.dart';
import 'package:tylog/vault_registry.dart';
import 'package:tylog/vault_storage.dart';
import 'package:tylog/workspace_controller.dart';

class _CountingStorage extends LocalVaultStorage {
  _CountingStorage(super.root);
  final writes = <String>[];
  bool countIndex = false;
  int indexLookups = 0;

  @override
  Future<bool> exists(String path) {
    if (countIndex && path == Vault.indexPath) indexLookups++;
    return super.exists(path);
  }

  @override
  Future<Uint8List> readBytes(String path) {
    if (countIndex && path == Vault.indexPath) indexLookups++;
    return super.readBytes(path);
  }

  @override
  Future<void> writeBytes(String path, List<int> bytes) {
    writes.add(path);
    return super.writeBytes(path, bytes);
  }
}

class _Inspector implements TypstInspector {
  @override
  Future<List<TypstMetadataRecord>> inspect(TypstDocumentInput input) async {
    final note = scanNote(input.path, input.source);
    return [
      TypstMetadataRecord(
        label: '<tylog-note>',
        value: {
          'schema': 1,
          'entity': 'note',
          'id': note.id,
          'title': note.title,
          'kind': note.kind,
        },
      ),
    ];
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'creation writes once, projects the assigned id, and avoids disk index',
    () async {
      final root = await Directory.systemTemp.createTemp('tylog-create-io-');
      addTearDown(() => root.delete(recursive: true));
      final storage = _CountingStorage(root);
      final database = TyLogDatabase(NativeDatabase.memory());
      final controller = WorkspaceController(
        taskScheduler: TaskScheduler(),
        inspector: _Inspector(),
        reconcileTasks: (_) async {},
        database: Future.value(database),
      );
      addTearDown(database.close);
      addTearDown(controller.dispose);
      await controller.openVault(
        VaultEntry(id: 'create-io', name: 'Create', path: root.path),
        storage: storage,
      );
      for (var i = 0; controller.index == null && i < 400; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(controller.index, isNotNull);
      storage.writes.clear();
      storage.countIndex = true;
      final path = await controller.createPage('Assigned', id: 'local-id');
      expect(storage.writes.where((p) => p == path), hasLength(1));
      expect(await storage.readText(path), contains('id: "local-id"'));
      expect(storage.indexLookups, 0);
      expect(controller.vault!.isStaleNote(path), isTrue);
      expect(controller.vault!.isPendingSyncWrite(path), isTrue);
      expect(
        (await database.select(database.nodes).get()).map((n) => n.id),
        contains('local-id'),
      );

      storage.indexLookups = 0;
      final automatic = await controller.createPage('Automatic');
      expect(storage.indexLookups, 0);
      expect(storage.writes.where((p) => p == automatic), hasLength(1));
    },
  );

  test('local allocations reserve ids across unindexed creations', () async {
    final root = await Directory.systemTemp.createTemp('tylog-create-ids-');
    addTearDown(() => root.delete(recursive: true));
    final storage = _CountingStorage(root)..countIndex = true;
    final vault = Vault.withStorage(storage);
    final now = DateTime(2026, 10, 13, 12);
    final first = vault.allocateNoteId('Привет', now: now, knownIds: {});
    final second = vault.allocateNoteId('Другой', now: now, knownIds: {});
    expect(second, '$first-2');
    expect(await vault.nextNoteId('Ещё', now: now, knownIds: {}), '$first-3');
    expect(storage.indexLookups, 0);
  });
}
