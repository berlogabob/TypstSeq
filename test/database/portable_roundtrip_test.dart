import 'dart:io';

import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/database/portable_import.dart';
import 'package:tylog/database/portable_snapshot.dart';
import 'package:tylog/database/tylog_database.dart';
import 'package:tylog_core/storage.dart';

void main() {
  late Directory root;
  late Future<TyLogDatabase> Function(String name) database;

  setUp(() {
    root = Directory.systemTemp.createTempSync('portable_roundtrip_');
    database = (name) => openDatabaseWithFile(File('${root.path}/$name.db'));
  });
  tearDown(() => root.deleteSync(recursive: true));

  test(
    'round trip preserves graph, revisions, bibliography, and attachment',
    () async {
      final sourceDb = await database('source');
      await _seed(sourceDb);
      final sourceVault = LocalVaultStorage(
        Directory('${root.path}/source-vault'),
      );
      await sourceVault.writeText('_system/bibliography.yml', 'book: source\n');
      await sourceVault.writeBytes('assets/paper.pdf', [1, 2, 3, 4]);

      final archive = await exportPortableSnapshot(
        database: sourceDb,
        storage: sourceVault,
      );
      await sourceDb.close();
      final targetDb = await database('target');
      addTearDown(targetDb.close);
      final targetVault = LocalVaultStorage(
        Directory('${root.path}/target-vault'),
      );
      final first = await importPortableSnapshot(
        database: targetDb,
        storage: targetVault,
        bytes: archive,
      );

      expect(first.hasConflicts, isFalse);
      expect(first.insertedRows, 7);
      expect(first.insertedFiles, 2);
      expect(await targetDb.select(targetDb.nodes).get(), hasLength(2));
      expect(await targetDb.select(targetDb.edges).get(), hasLength(1));
      expect(await targetDb.select(targetDb.revisions).get(), hasLength(3));
      expect(
        await targetVault.readText('_system/bibliography.yml'),
        'book: source\n',
      );
      expect(
        await targetVault.hash('assets/paper.pdf'),
        await sourceVault.hash('assets/paper.pdf'),
      );

      final second = await importPortableSnapshot(
        database: targetDb,
        storage: targetVault,
        bytes: archive,
      );
      expect(second.hasConflicts, isFalse);
      expect(second.insertedRows, 0);
      expect(second.insertedFiles, 0);
      expect(second.unchangedRows, 7);
      expect(second.unchangedFiles, 2);
    },
  );

  test('divergent stable ID reports conflict and changes nothing', () async {
    final sourceDb = await database('source-conflict');
    await _seed(sourceDb);
    final sourceVault = LocalVaultStorage(
      Directory('${root.path}/source-files'),
    );
    await sourceVault.writeBytes('assets/paper.pdf', [1]);
    final archive = await exportPortableSnapshot(
      database: sourceDb,
      storage: sourceVault,
    );
    await sourceDb.close();
    final targetDb = await database('target-conflict');
    addTearDown(targetDb.close);
    await _seed(targetDb);
    await (targetDb.update(targetDb.nodes)
          ..where((row) => row.id.equals('node-a')))
        .write(const NodesCompanion(content: Value('local divergent content')));

    final report = await importPortableSnapshot(
      database: targetDb,
      storage: LocalVaultStorage(Directory('${root.path}/target-files')),
      bytes: archive,
    );

    expect(report.hasConflicts, isTrue);
    expect(report.plan.conflicts, hasLength(1));
    final conflict = report.plan.conflicts.single;
    expect(
      conflict.local!.value.toString(),
      contains('local divergent content'),
    );
    expect(conflict.incoming!.value.toString(), contains('Linked content'));
    expect((await targetDb.select(targetDb.nodes).get()), hasLength(2));
    expect(
      (await (targetDb.select(
        targetDb.nodes,
      )..where((row) => row.id.equals('node-a'))).getSingle()).content,
      'local divergent content',
    );
  });

  test(
    'failed vault write rolls back database rows and created files',
    () async {
      final sourceDb = await database('source-failure');
      await _seed(sourceDb);
      final sourceVault = LocalVaultStorage(
        Directory('${root.path}/failure-source'),
      );
      await sourceVault.writeBytes('assets/a.bin', [1]);
      await sourceVault.writeBytes('assets/b.bin', [2]);
      final archive = await exportPortableSnapshot(
        database: sourceDb,
        storage: sourceVault,
      );
      await sourceDb.close();
      final targetDb = await database('target-failure');
      addTearDown(targetDb.close);
      final targetVault = _FailingStorage(
        Directory('${root.path}/failure-target'),
      );

      await expectLater(
        importPortableSnapshot(
          database: targetDb,
          storage: targetVault,
          bytes: archive,
        ),
        throwsStateError,
      );
      expect(await targetDb.select(targetDb.nodes).get(), isEmpty);
      expect(
        (await targetVault.list(
          recursive: true,
        )).where((entry) => !entry.isDirectory),
        isEmpty,
      );
    },
  );
}

class _FailingStorage extends LocalVaultStorage {
  _FailingStorage(super.root);

  var writes = 0;

  @override
  Future<void> writeBytes(String path, List<int> bytes) async {
    if (++writes == 2) throw StateError('forced write failure');
    await super.writeBytes(path, bytes);
  }
}

Future<void> _seed(TyLogDatabase database) async {
  const source = SourceData(
    id: 'source-1',
    kind: 'book',
    title: 'Source',
    locator: 'isbn:1',
    attributesJson: '{"citationKey":"source"}',
    createdAtMs: 1,
    updatedAtMs: 2,
  );
  const first = NodeData(
    id: 'node-a',
    type: 'note',
    title: 'A',
    content: 'Linked content',
    attributesJson: '{"annotation":{"page":4,"offset":12}}',
    createdAtMs: 1,
    updatedAtMs: 2,
  );
  const second = NodeData(
    id: 'node-b',
    type: 'note',
    title: 'B',
    content: 'Target',
    attributesJson: '{}',
    createdAtMs: 1,
    updatedAtMs: 2,
  );
  await database.transaction(() async {
    await database.into(database.sources).insert(source);
    await database.into(database.nodes).insert(first);
    await database.into(database.nodes).insert(second);
    await database
        .into(database.edges)
        .insert(
          const EdgeData(
            id: 'edge-1',
            fromNodeId: 'node-a',
            toNodeId: 'node-b',
            type: 'links',
            attributesJson: '{}',
            createdAtMs: 2,
            updatedAtMs: 2,
          ),
        );
    await database
        .into(database.revisions)
        .insert(
          const RevisionData(
            id: 'z-parent',
            entityKind: 'node',
            entityId: 'node-a',
            payloadJson: '{"content":"one"}',
            createdAtMs: 1,
          ),
        );
    await database
        .into(database.revisions)
        .insert(
          const RevisionData(
            id: 'm-child',
            entityKind: 'node',
            entityId: 'node-a',
            parentRevisionId: 'z-parent',
            payloadJson: '{"content":"two"}',
            createdAtMs: 2,
          ),
        );
    await database
        .into(database.revisions)
        .insert(
          const RevisionData(
            id: 'a-grandchild',
            entityKind: 'node',
            entityId: 'node-a',
            parentRevisionId: 'm-child',
            payloadJson: '{"content":"three"}',
            createdAtMs: 3,
          ),
        );
  });
}
