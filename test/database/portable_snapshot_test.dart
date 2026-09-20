import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/database/portable_snapshot.dart';
import 'package:tylog/database/tylog_database.dart';
import 'package:tylog_core/storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory directory;
  late TyLogDatabase database;
  late LocalVaultStorage storage;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('tylog_snapshot_');
    database = TyLogDatabase(NativeDatabase.memory());
    storage = LocalVaultStorage(directory);
    await database
        .into(database.sources)
        .insert(
          const SourcesCompanion(
            id: Value('source-1'),
            kind: Value('paper'),
            title: Value('A paper'),
            locator: Value('https://example.test/paper'),
            attributesJson: Value('{"year":2026}'),
            createdAtMs: Value(1),
            updatedAtMs: Value(2),
          ),
        );
    await database
        .into(database.nodes)
        .insert(
          const NodesCompanion(
            id: Value('node-1'),
            type: Value('note'),
            title: Value('A note'),
            content: Value('body'),
            attributesJson: Value('{"source":"source-1"}'),
            createdAtMs: Value(3),
            updatedAtMs: Value(4),
          ),
        );
    await database
        .into(database.edges)
        .insert(
          const EdgesCompanion(
            id: Value('edge-1'),
            fromNodeId: Value('node-1'),
            toNodeId: Value('node-1'),
            type: Value('supports'),
            attributesJson: Value('{}'),
            createdAtMs: Value(5),
            updatedAtMs: Value(6),
          ),
        );
    await database
        .into(database.revisions)
        .insert(
          const RevisionsCompanion(
            id: Value('revision-1'),
            entityKind: Value('node'),
            entityId: Value('node-1'),
            payloadJson: Value('{"content":"body"}'),
            createdAtMs: Value(7),
          ),
        );
    await storage.writeText('notes/a.typ', 'note');
    await storage.writeText('notes/portable-export-guide.typ', 'user content');
    await storage.writeBytes('assets/blob.bin', [0, 1, 2, 255]);
    await storage.writeText('_index/index.json', 'derived');
    await storage.writeText('.tylog/vault.lock', 'locked');
    await storage.writeText('.tylog/sync_state.json', 'device-local');
    await storage.writeText('.tylog/portable-export-1.zip', 'temporary');
  });

  tearDown(() async {
    await database.close();
    await directory.delete(recursive: true);
  });

  test('exports deterministic complete rows and portable files', () async {
    final first = await exportPortableSnapshot(
      database: database,
      storage: storage,
    );
    final second = await exportPortableSnapshot(
      database: database,
      storage: storage,
    );
    expect(first, orderedEquals(second));

    final snapshot = parsePortableSnapshot(first);
    expect(snapshot.schemaVersion, 6);
    expect(snapshot.sources.single['attributesJson'], '{"year":2026}');
    expect(snapshot.nodes.single['content'], 'body');
    expect(snapshot.edges.single['fromNodeId'], 'node-1');
    expect(snapshot.revisions.single['payloadJson'], '{"content":"body"}');
    expect(
      snapshot.vaultFiles.keys,
      containsAll([
        'notes/a.typ',
        'notes/portable-export-guide.typ',
        'assets/blob.bin',
      ]),
    );
    expect(snapshot.vaultFiles.keys, isNot(contains('_index/index.json')));
    expect(snapshot.vaultFiles.keys, isNot(contains('.tylog/vault.lock')));
    expect(snapshot.vaultFiles.keys, isNot(contains('.tylog/sync_state.json')));
    expect(snapshot.entries.keys, contains('records/nodes.jsonl'));
  });

  test('rejects a manifest with an unlisted archive entry', () async {
    final bytes = await exportPortableSnapshot(
      database: database,
      storage: storage,
    );
    final archive = ZipDecoder().decodeBytes(bytes);
    archive.add(ArchiveFile.bytes('vault/extra.bin', [1]));
    final changed = ZipEncoder().encodeBytes(
      archive,
      modified: DateTime.utc(1980, 1, 1),
    );
    expect(
      () => parsePortableSnapshot(changed),
      throwsA(isA<FormatException>()),
    );
  });

  test('rejects vault paths that collide by letter case', () async {
    final bytes = await exportPortableSnapshot(
      database: database,
      storage: storage,
    );
    final archive = ZipDecoder().decodeBytes(bytes);
    final manifestFile = archive.find('manifest.json')!;
    final manifest = jsonDecode(utf8.decode(manifestFile.readBytes()!)) as Map;
    const content = [7];
    (manifest['entries'] as List).add({
      'path': 'vault/ASSETS/BLOB.BIN',
      'size': content.length,
      'sha256': sha256.convert(content).toString(),
    });
    archive.add(ArchiveFile.string('manifest.json', jsonEncode(manifest)));
    archive.add(ArchiveFile.bytes('vault/ASSETS/BLOB.BIN', content));

    expect(
      () => parsePortableSnapshot(
        ZipEncoder().encodeBytes(archive, modified: DateTime.utc(1980, 1, 1)),
      ),
      throwsA(isA<FormatException>()),
    );
  });
}
