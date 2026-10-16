import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:tylog_core/tylog_core.dart';

class _CountingStorage extends LocalVaultStorage {
  _CountingStorage(super.root);
  int searchReads = 0;
  int searchWrites = 0;

  @override
  Future<Uint8List> readBytes(String path) {
    if (path == TylogVaultPaths.searchIndex) searchReads++;
    return super.readBytes(path);
  }

  @override
  Future<void> writeBytes(String path, List<int> bytes) {
    if (path == TylogVaultPaths.searchIndex) searchWrites++;
    return super.writeBytes(path, bytes);
  }
}

void main() {
  test(
    'post-sync rescan indexes a new note and preserves unchanged caches',
    () async {
      final root = await Directory.systemTemp.createTemp('tylog-search-new-');
      addTearDown(() => root.delete(recursive: true));
      final storage = _CountingStorage(root);
      await storage.writeText('notes/a.typ', '= A\n\noriginalword');
      final maintenance = VaultMaintenance(storage, publishDonor: false);
      Future<List<VaultMaintenanceEvent>> scan() =>
          maintenance.run(validate: false, sweep: false).toList();
      final initial = await scan();
      final before = initial.whereType<MaintenanceIndexed>().single.index;
      final beforeSearch = initial
          .whereType<MaintenanceSearchBuilt>()
          .single
          .search;

      const path = 'notes/TyLog sync test.typ';
      await storage.writeText(
        path,
        '= TyLog sync test\n\nrevision check from mac 1356',
      );
      final events = await scan();
      final index = events.whereType<MaintenanceIndexed>().single.index;
      final search = events.whereType<MaintenanceSearchBuilt>().single.search;
      expect(index.notesByPath, contains(path));
      expect(identical(index, before), isFalse);
      expect(identical(search, beforeSearch), isFalse);
      for (final query in ['sync test', 'revision check']) {
        expect(search.search(query).map((hit) => hit.path), contains(path));
      }
      expect(search.search('originalword').single.path, 'notes/a.typ');

      final unchanged = await scan();
      expect(
        unchanged.whereType<MaintenanceIndexed>().single.index,
        same(index),
      );
      expect(
        unchanged.whereType<MaintenanceSearchBuilt>().single.search,
        same(search),
      );
      await maintenance.flushSearch();
      final loaded = await PkmsSearchIndex.loadStorage(
        storage,
        TylogVaultPaths.searchIndex,
      );
      expect(loaded.search('revision check').single.path, path);
    },
  );

  test(
    'one changed note stays in memory until flush; stale disk recovers',
    () async {
      final root = await Directory.systemTemp.createTemp('tylog-search-cache-');
      addTearDown(() => root.delete(recursive: true));
      final storage = _CountingStorage(root);
      await storage.writeText('notes/a.typ', '= A\n\noldword');
      await storage.writeText('notes/b.typ', '= B\n\nuntouched');
      // Seed an existing cache so the first pass really loads it.
      await (await PkmsSearchIndex.buildStorage(
        storage,
        await scanVaultStorage(storage),
      )).saveStorage(storage, TylogVaultPaths.searchIndex);
      storage.searchReads = storage.searchWrites = 0;
      final maintenance = VaultMaintenance(storage, publishDonor: false);
      await maintenance.run(validate: false, sweep: false).toList();
      expect(storage.searchReads, 1);
      expect(storage.searchWrites, 0);

      await storage.writeText('notes/a.typ', '= A\n\nchangedword');
      storage.searchReads = storage.searchWrites = 0;
      final events = await maintenance
          .run(stale: {'notes/a.typ'}, validate: false, sweep: false)
          .toList();
      final search = events.whereType<MaintenanceSearchBuilt>().single.search;
      expect(search.search('changedword').single.path, 'notes/a.typ');
      expect(storage.searchReads, 0);
      expect(storage.searchWrites, 0);

      // Simulate a crash before flush: disk is old, the scanned index is new.
      final stale = await PkmsSearchIndex.loadStorage(
        storage,
        TylogVaultPaths.searchIndex,
      );
      expect(stale.search('changedword'), isEmpty);
      final recovered = await PkmsSearchIndex.buildStorage(
        storage,
        maintenance.lastBuiltIndex!,
        previous: stale,
      );
      expect(recovered.search('changedword').single.path, 'notes/a.typ');
      expect(recovered.search('untouched').single.path, 'notes/b.typ');

      storage.searchWrites = 0;
      await maintenance.flushSearch();
      expect(storage.searchWrites, 1);
      final loaded = await PkmsSearchIndex.loadStorage(
        storage,
        TylogVaultPaths.searchIndex,
      );
      expect(loaded.search('changedword').single.path, 'notes/a.typ');
      await maintenance.flushSearch();
      expect(storage.searchWrites, 1);
    },
  );
}
