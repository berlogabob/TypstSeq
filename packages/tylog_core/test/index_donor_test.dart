import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:tylog_core/tylog_core.dart';

VaultIndex _index() => VaultIndex(
  notesByPath: {
    'notes/a.typ': const NoteRef(
      id: 'a',
      path: 'notes/a.typ',
      title: 'Alpha',
      outgoingLinks: [],
      contentHash: 'hash-a',
      metadataSource: 'typst-query',
    ),
  },
  backlinksByTarget: const {},
  tasks: const [],
);

String _donorJson({
  int schema = indexDonorSchema,
  int version = kVaultIndexVersion,
  int queryVersion = kVaultQueryVersion,
}) => jsonEncode({
  'schema': schema,
  'indexVersion': version,
  'queryVersion': queryVersion,
  'synonymsHash': '',
  'notes': [
    const NoteRef(
      id: 'peer',
      path: 'notes/peer.typ',
      title: 'FROM PEER',
      outgoingLinks: [],
      contentHash: 'hash-peer',
      metadataSource: 'typst-query',
    ).toJson(),
  ],
  'tasks': const [],
});

/// Refuses to delete one path, to prove a prune survives it.
class _RefusingDeleteStorage extends LocalVaultStorage {
  _RefusingDeleteStorage(super.root, {required this.refuse});

  final String refuse;

  @override
  Future<void> delete(String path) async {
    if (path == refuse) throw const FileSystemException('locked');
    return super.delete(path);
  }
}

/// Refuses to write the donor at all.
class _RefusingWriteStorage extends LocalVaultStorage {
  _RefusingWriteStorage(super.root);

  @override
  Future<void> writeText(String path, String contents) async {
    if (path.startsWith(TylogVaultPaths.indexDonors)) {
      throw const FileSystemException('read-only');
    }
    return super.writeText(path, contents);
  }
}

void main() {
  late Directory root;
  late LocalVaultStorage storage;
  late IndexDonorStore donors;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('tylog-donor');
    storage = LocalVaultStorage(root);
    await storage.createDirectory(TylogVaultPaths.indexDonors);
    donors = IndexDonorStore(storage);
  });

  tearDown(() => root.delete(recursive: true));

  String path(String id) => '${TylogVaultPaths.indexDonors}/$id.json';

  /// Ages a donor past [IndexDonorStore.staleDonorAge] so the prune may touch
  /// it. A fresh peer donor is deliberately untouchable.
  void age(String id) => File('${root.path}/${path(id)}').setLastModifiedSync(
    DateTime.now().subtract(const Duration(days: 30)),
  );

  test('publishing writes a donor a peer can read back', () async {
    await donors.publish('desktop', _index());

    final json =
        (jsonDecode(await storage.readText(path('desktop'))) as Map)
            .cast<String, Object?>();
    expect(json['schema'], indexDonorSchema);
    expect(json['indexVersion'], kVaultIndexVersion);
    expect((json['notes'] as List), hasLength(1));

    // A peer (different device id) merges it.
    final reused = await IndexDonorStore(storage).load('phone');
    expect(reused?.notesByPath['notes/a.typ']?.title, 'Alpha');
  });

  test('one undeletable donor does not abort the whole prune', () async {
    // The delete used to sit inside a catch wrapping the entire loop, so an
    // unlucky first file meant every donor after it stayed - silently, and
    // forever, because the caller discards the count.
    final storage = _RefusingDeleteStorage(root, refuse: path('locked'));
    await storage.createDirectory(TylogVaultPaths.indexDonors);
    for (final id in ['locked', 'dead-a', 'dead-b']) {
      await storage.writeText(path(id), _donorJson(schema: 1));
      File('${root.path}/${path(id)}').setLastModifiedSync(
        DateTime.now().subtract(const Duration(days: 30)),
      );
    }

    final deleted = await IndexDonorStore(storage).pruneUnusable('mine');

    expect(deleted, 2, reason: 'the other two are still reclaimed');
    expect(await storage.exists(path('locked')), isTrue);
    expect(await storage.exists(path('dead-a')), isFalse);
    expect(await storage.exists(path('dead-b')), isFalse);
  });

  test('a publish failure is reportable, not just survivable', () async {
    final storage = _RefusingWriteStorage(root);
    await storage.createDirectory(TylogVaultPaths.indexDonors);
    final store = IndexDonorStore(storage);

    await store.publish('desktop', _index());

    expect(
      store.lastPublishError,
      isNotNull,
      reason: 'a device that stops sharing makes every peer recompile',
    );
  });

  test('a peer donor written moments ago is never pruned', () async {
    // The P30 dropped its unusable replica of the desktop's donor seconds
    // after the desktop had replaced it with a readable one, then propagated
    // that deletion to the server - removing the one file the whole fleet was
    // waiting on. A donor lives in a shared folder; deleting someone else's
    // needs proof that nobody is still publishing it.
    await storage.writeText(path('desktop'), _donorJson(schema: 1));

    expect(await donors.pruneUnusable('mine'), 0);
    expect(await storage.exists(path('desktop')), isTrue);
  });

  test('a donor survives a derive-only index bump', () async {
    // The whole point of the split: v8 and v9 changed only derivation, yet
    // every donor died and both phones recompiled thousands of notes to
    // recover metadata they were already holding.
    await storage.writeText(
      path('desktop'),
      _donorJson(version: kVaultIndexVersion - 1),
    );

    final store = IndexDonorStore(storage);
    final reused = await store.load('phone');
    expect(reused, isNotNull);
    expect(reused!.notesByPath['notes/peer.typ']?.title, 'FROM PEER');
    expect(
      reused.version,
      lessThan(kVaultIndexVersion),
      reason: 'the scanner must see it as needing re-derivation',
    );
    expect(store.lastReuse.notes, 1);
  });

  test('a donor from an older query version is not reusable', () async {
    await storage.writeText(
      path('desktop'),
      _donorJson(
        version: kVaultIndexVersion - 1,
        queryVersion: kVaultQueryVersion - 1,
      ),
    );
    final store = IndexDonorStore(storage);
    expect(await store.load('phone'), isNull);
    expect(store.lastReuse.skipped, 1);
  });

  test('a donor from a different query is never merged', () async {
    // Even at the current index version: its queryFacts came from a query we
    // cannot re-derive from, and merging them would launder those facts into
    // this device's own index under our current query version.
    await storage.writeText(
      path('peer'),
      _donorJson(queryVersion: kVaultQueryVersion + 1),
    );
    final store = IndexDonorStore(storage);
    expect(await store.load('mine'), isNull);
    expect(store.lastReuse.skipped, 1);
  });

  test('pruning keeps a donor that is still re-derivable', () async {
    await storage.writeText(
      path('peer'),
      _donorJson(version: kVaultIndexVersion - 1),
    );
    expect(await IndexDonorStore(storage).pruneUnusable('desktop'), 0);
    expect(await storage.exists(path('peer')), isTrue);
  });

  test('a device never merges its own donor', () async {
    await donors.publish('desktop', _index());
    expect(await IndexDonorStore(storage).load('desktop'), isNull);
  });

  // `_system/index/` syncs, so a donor this build can never read is downloaded
  // by every device forever. Measured at 5.7 MB of dead weight on the real
  // vault before this pruning existed.
  test('pruning deletes unusable donors and keeps the rest', () async {
    await storage.writeText(path('old-schema'), _donorJson(schema: 1));
    await storage.writeText(
      path('old-version'),
      // Unusable now means the *query* is stale: a merely older index version
      // is re-derivable and must survive.
      _donorJson(version: 1, queryVersion: kVaultQueryVersion - 1),
    );
    await storage.writeText(path('corrupt'), 'not json at all');
    await storage.writeText(path('current'), _donorJson());
    await storage.writeText(path('mine'), _donorJson());
    for (final id in ['old-schema', 'old-version', 'corrupt', 'current']) {
      age(id);
    }

    final deleted = await donors.pruneUnusable('mine');

    expect(deleted, 3);
    expect(await storage.exists(path('old-schema')), isFalse);
    expect(await storage.exists(path('old-version')), isFalse);
    expect(await storage.exists(path('corrupt')), isFalse);
    expect(
      await storage.exists(path('current')),
      isTrue,
      reason: 'a readable current-version peer donor must survive',
    );
    expect(
      await storage.exists(path('mine')),
      isTrue,
      reason: 'never delete this device\'s own donor',
    );
  });

  test('publishing prunes as a side effect', () async {
    await storage.writeText(path('old-schema'), _donorJson(schema: 1));
    age('old-schema');
    await donors.publish('desktop', _index());
    expect(await storage.exists(path('old-schema')), isFalse);
    expect(await storage.exists(path('desktop')), isTrue);
  });

  // The mechanism was dead for days without anyone noticing, because falling
  // back to recompiling everything looks exactly like a cache hit.
  test('load reports what it reused and what it skipped', () async {
    await storage.writeText(path('peer'), _donorJson());
    await storage.writeText(
      path('stale'),
      _donorJson(version: 1, queryVersion: kVaultQueryVersion - 1),
    );

    final store = IndexDonorStore(storage);
    await store.load('mine');

    expect(store.lastReuse.notes, 1);
    expect(store.lastReuse.devices, 1);
    expect(store.lastReuse.skipped, 1);
    expect(store.lastReuse.isEmpty, isFalse);
    expect(store.lastReuse.toString(), contains('reused 1 notes'));
  });
}
