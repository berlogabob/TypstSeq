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
}) => jsonEncode({
  'schema': schema,
  'indexVersion': version,
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

  test('a device never merges its own donor', () async {
    await donors.publish('desktop', _index());
    expect(await IndexDonorStore(storage).load('desktop'), isNull);
  });

  // `_system/index/` syncs, so a donor this build can never read is downloaded
  // by every device forever. Measured at 5.7 MB of dead weight on the real
  // vault before this pruning existed.
  test('pruning deletes unusable donors and keeps the rest', () async {
    await storage.writeText(path('old-schema'), _donorJson(schema: 1));
    await storage.writeText(path('old-version'), _donorJson(version: 1));
    await storage.writeText(path('corrupt'), 'not json at all');
    await storage.writeText(path('current'), _donorJson());
    await storage.writeText(path('mine'), _donorJson());

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
    await donors.publish('desktop', _index());
    expect(await storage.exists(path('old-schema')), isFalse);
    expect(await storage.exists(path('desktop')), isTrue);
  });

  // The mechanism was dead for days without anyone noticing, because falling
  // back to recompiling everything looks exactly like a cache hit.
  test('load reports what it reused and what it skipped', () async {
    await storage.writeText(path('peer'), _donorJson());
    await storage.writeText(path('stale'), _donorJson(version: 1));

    final store = IndexDonorStore(storage);
    await store.load('mine');

    expect(store.lastReuse.notes, 1);
    expect(store.lastReuse.devices, 1);
    expect(store.lastReuse.skipped, 1);
    expect(store.lastReuse.isEmpty, isFalse);
    expect(store.lastReuse.toString(), contains('reused 1 notes'));
  });
}
