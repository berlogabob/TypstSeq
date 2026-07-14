import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/scanner.dart';
import 'package:tylog/task_scheduler.dart';
import 'package:tylog/vault_registry.dart';
import 'package:tylog/vault_storage.dart';
import 'package:tylog/workspace_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'controller owns open, source, save, and index with fake boundaries',
    () async {
      final storage = _MemoryStorage();
      final inspector = _FakeInspector();
      final controller = WorkspaceController(
        taskScheduler: TaskScheduler(),
        inspector: inspector,
        reconcileTasks: (_) async {},
      );
      addTearDown(controller.dispose);
      const entry = VaultEntry(
        id: 'fake',
        name: 'Fake vault',
        path: '/not-used',
      );

      await controller.openVault(entry, storage: storage);

      expect(controller.vault, isNotNull);
      expect(controller.note, startsWith('daily/'));
      expect(controller.source, contains('#import "/_system/tylog.typ"'));
      expect(controller.index?.notes, hasLength(1));
      expect(inspector.calls, 1);

      controller.edit('${controller.source}\nController edit.\n');
      expect(controller.dirty, isTrue);
      await controller.save(syncAfter: false);
      expect(controller.dirty, isFalse);
      expect(
        await storage.readText(controller.note!),
        contains('Controller edit.'),
      );

      await controller.refreshIndex(force: true);
      expect(controller.index?.notes.single.metadataSource, 'typst-query');
      expect(inspector.calls, 2);
    },
  );

  test(
    'registered Android vault is never recreated when access is empty',
    () async {
      final storage = _MemoryStorage();
      final controller = WorkspaceController(
        taskScheduler: TaskScheduler(),
        inspector: _FakeInspector(),
        reconcileTasks: (_) async {},
      );
      addTearDown(controller.dispose);

      await controller.openVault(
        const VaultEntry(
          id: 'android',
          name: 'Android vault',
          path: '',
          storageKind: 'android-tree',
          treeUri: 'content://test/tree',
        ),
        storage: storage,
      );

      expect(controller.vault, isNull);
      expect(controller.status, startsWith('Open failed:'));
      expect(storage._directories, {''});
      expect(storage._files, isEmpty);
    },
  );
}

class _FakeInspector implements TypstInspector {
  int calls = 0;

  @override
  Future<List<TypstMetadataRecord>> inspect(TypstDocumentInput input) async {
    calls++;
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
          'date': note.date,
          'tags': note.tags,
          'aliases': note.aliases,
          'properties': note.properties,
        },
      ),
    ];
  }
}

class _MemoryStorage extends VaultStorage {
  final Map<String, Uint8List> _files = {};
  final Set<String> _directories = {''};

  @override
  Future<void> createDirectory(String path) async {
    if (path.isEmpty) return;
    final parts = path.split('/');
    for (var i = 1; i <= parts.length; i++) {
      _directories.add(parts.take(i).join('/'));
    }
  }

  @override
  Future<void> delete(String path) async {
    _files.removeWhere((key, _) => key == path || key.startsWith('$path/'));
    _directories.removeWhere((key) => key == path || key.startsWith('$path/'));
  }

  @override
  Future<bool> exists(String path) async =>
      _files.containsKey(path) || _directories.contains(path);

  @override
  Future<String> hash(String path) async => base64.encode(_files[path]!);

  @override
  Future<List<VaultStorageEntry>> list({
    String path = '',
    bool recursive = false,
  }) async {
    final prefix = path.isEmpty ? '' : '$path/';
    bool included(String candidate) {
      if (!candidate.startsWith(prefix) || candidate == path) return false;
      return recursive || !candidate.substring(prefix.length).contains('/');
    }

    return [
      for (final directory in _directories)
        if (included(directory))
          VaultStorageEntry(path: directory, isDirectory: true),
      for (final entry in _files.entries)
        if (included(entry.key))
          VaultStorageEntry(
            path: entry.key,
            isDirectory: false,
            size: entry.value.length,
            modified: DateTime.utc(2026, 7, 14),
          ),
    ];
  }

  @override
  Future<Uint8List> readBytes(String path) async => _files[path]!;

  @override
  Future<VaultStorageEntry?> stat(String path) async {
    final bytes = _files[path];
    if (bytes != null) {
      return VaultStorageEntry(
        path: path,
        isDirectory: false,
        size: bytes.length,
        modified: DateTime.utc(2026, 7, 14),
      );
    }
    return _directories.contains(path)
        ? VaultStorageEntry(path: path, isDirectory: true)
        : null;
  }

  @override
  Future<void> writeBytes(String path, List<int> bytes) async {
    final slash = path.lastIndexOf('/');
    if (slash > 0) await createDirectory(path.substring(0, slash));
    _files[path] = Uint8List.fromList(bytes);
  }
}
