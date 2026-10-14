import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/nextcloud_sync.dart';
import 'package:tylog/vault.dart';
import 'package:tylog/vault_storage.dart';

const _statePath = '.tylog/sync_state.json';
const _config = NextcloudConfig(
  serverUrl: 'https://example.com',
  username: 'test',
  password: 'test',
);

void main() {
  late _CountingStorage storage;
  late Vault vault;
  late NextcloudSync sync;

  setUp(() async {
    final root = await Directory.systemTemp.createTemp('sync-state-cache-');
    addTearDown(() => root.delete(recursive: true));
    storage = _CountingStorage(LocalVaultStorage(root));
    vault = Vault.withStorage(storage);
    sync = NextcloudSync(_config);
    await storage.writeText(
      _statePath,
      jsonEncode({
        'rootEtag': 'root-1',
        'folders': {'': 'folder-1', 'cafe\u0301': 'folder-2'},
        'cursors': {
          'notes/a.typ': const SyncCursor(remoteEtag: 'a').toJson(),
          'notes/b.typ': const SyncCursor(remoteEtag: 'b').toJson(),
          'notes/cafe\u0301.typ': const SyncCursor(remoteEtag: 'c').toJson(),
        },
      }),
    );
  });

  test(
    'caches reads, isolates maps, reloads changes and invalidates saves',
    () async {
      final first = await loadSyncStateForTesting(sync, vault);
      expect(first.cursors, hasLength(3));
      expect(first.cursors['notes/café.typ']!.remoteEtag, 'c');
      expect(first.folders['café'], 'folder-2');
      first.cursors.clear();
      first.folders.clear();

      // Poll ticks may create a new engine, but retain the same Vault.
      final second = await loadSyncStateForTesting(
        NextcloudSync(_config),
        vault,
      );
      expect(storage.stateReads, 1);
      expect(second.cursors, hasLength(3));
      expect(second.folders[''], 'folder-1');
      second.cursors.clear();
      second.folders.clear();
      final third = await loadSyncStateForTesting(sync, vault);
      expect(storage.stateReads, 1);
      expect(third.cursors, hasLength(3));
      expect(third.folders[''], 'folder-1');

      final previousSize = (await storage.stat(_statePath))!.size;
      await storage.writeText(
        _statePath,
        jsonEncode({
          'rootEtag': 'changed-root',
          'folders': {'': 'changed-folder'},
          'cursors': {
            'notes/new.typ': const SyncCursor(remoteEtag: 'new').toJson(),
          },
        }),
      );
      expect((await storage.stat(_statePath))!.size, isNot(previousSize));
      final changed = await loadSyncStateForTesting(sync, vault);
      expect(storage.stateReads, 2);
      expect(changed.cursors.keys, ['notes/new.typ']);
      expect(changed.cursors['notes/new.typ']!.remoteEtag, 'new');
      expect(changed.rootEtag, 'changed-root');
      expect(changed.folders[''], 'changed-folder');

      // Hold metadata constant so only explicit save invalidation can reload.
      storage.fixedStat = await storage.stat(_statePath);
      await saveSyncStateForTesting(
        sync,
        vault,
        changed.cursors,
        rootEtag: 'saved-root',
        folders: {'': 'saved-folder'},
      );
      final saved = await loadSyncStateForTesting(sync, vault);
      expect(storage.stateReads, 3);
      expect(saved.rootEtag, 'saved-root');
      expect(saved.folders[''], 'saved-folder');
      expect(saved.legacy, isFalse);
      await loadSyncStateForTesting(sync, vault);
      expect(storage.stateReads, 3);
    },
  );

  test(
    'reloads modified timestamps, remote configurations and vault instances',
    () async {
      await loadSyncStateForTesting(sync, vault);
      final stat = (await storage.stat(_statePath))!;
      storage.fixedStat = VaultStorageEntry(
        path: stat.path,
        isDirectory: false,
        size: stat.size,
        modified: stat.modified!.add(const Duration(seconds: 1)),
      );
      await loadSyncStateForTesting(sync, vault);
      expect(storage.stateReads, 2);
      await loadSyncStateForTesting(
        NextcloudSync(
          const NextcloudConfig(
            serverUrl: 'https://other.example.com',
            username: 'test',
            password: 'test',
          ),
        ),
        vault,
      );
      expect(storage.stateReads, 3);
      await loadSyncStateForTesting(sync, Vault.withStorage(storage));
      expect(storage.stateReads, 4);
    },
  );

  for (final missing in ['size', 'modified', 'stat']) {
    test('does not cache when $missing is unavailable', () async {
      storage.missingMetadata = missing;
      await loadSyncStateForTesting(sync, vault);
      await loadSyncStateForTesting(sync, vault);
      expect(storage.stateReads, 2);
    });
  }

  for (final source in ['{', '{"cursors":{},"remoteKey":"other"}']) {
    test(
      'does not cache recovered or remote mismatch state: $source',
      () async {
        await storage.writeText(_statePath, source);
        final first = await loadSyncStateForTesting(sync, vault);
        final second = await loadSyncStateForTesting(sync, vault);
        expect(storage.stateReads, 2);
        expect(first.recovered, source == '{');
        expect(second.remoteMismatch, source != '{');
      },
    );
  }

  test('does not cache a missing file', () async {
    await storage.delete(_statePath);
    expect((await loadSyncStateForTesting(sync, vault)).cursors, isEmpty);
    expect(storage.stateReads, 0);
    await storage.writeText(_statePath, '{"cursors":{"new":{}}}');
    expect((await loadSyncStateForTesting(sync, vault)).cursors.keys, ['new']);
    expect(storage.stateReads, 1);
  });
}

class _CountingStorage extends VaultStorage {
  _CountingStorage(this.delegate);

  final LocalVaultStorage delegate;
  int stateReads = 0;
  VaultStorageEntry? fixedStat;
  String? missingMetadata;

  @override
  Future<String> readText(String path) {
    if (path == _statePath) stateReads++;
    return delegate.readText(path);
  }

  @override
  Future<VaultStorageEntry?> stat(String path) async {
    final stat = fixedStat ?? await delegate.stat(path);
    if (stat == null || missingMetadata == 'stat') return null;
    return VaultStorageEntry(
      path: stat.path,
      isDirectory: stat.isDirectory,
      size: missingMetadata == 'size' ? null : stat.size,
      modified: missingMetadata == 'modified' ? null : stat.modified,
    );
  }

  @override
  Future<bool> exists(String path) => delegate.exists(path);

  @override
  Future<void> createDirectory(String path) => delegate.createDirectory(path);

  @override
  Future<List<VaultStorageEntry>> list({
    String path = '',
    bool recursive = false,
  }) => delegate.list(path: path, recursive: recursive);

  @override
  Future<Uint8List> readBytes(String path) => delegate.readBytes(path);

  @override
  Future<void> writeBytes(String path, List<int> bytes) =>
      delegate.writeBytes(path, bytes);

  @override
  Future<void> delete(String path) => delegate.delete(path);

  @override
  Future<String> hash(String path) => delegate.hash(path);
}
