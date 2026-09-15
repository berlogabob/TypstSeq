import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:tylog/database/tylog_database.dart';

void main() {
  late Directory directory;
  late TyLogDatabase database;

  setUp(() async {
    directory = Directory.systemTemp.createTempSync('tylog_edit_test_');
    database = await openDatabaseWithFile(File('${directory.path}/tylog.db'));
  });

  tearDown(() async {
    await database.close();
    directory.deleteSync(recursive: true);
  });

  test('edit commits content, revision, outbox, and invalidation', () async {
    await database.commitNodeEdit(
      node: _node('first'),
      revision: _revision('revision-1', '{"content":"first"}'),
    );

    expect(
      (await database.select(database.nodes).getSingle()).content,
      'first',
    );
    expect(await database.select(database.revisions).get(), hasLength(1));
    expect(await database.select(database.outboxEntries).get(), hasLength(1));
    expect(
      await database.select(database.derivedInvalidations).get(),
      hasLength(1),
    );
  });

  test('any failed edit rolls back every write', () async {
    await database.commitNodeEdit(
      node: _node('first'),
      revision: _revision('revision-1', '{"content":"first"}'),
    );

    await expectLater(
      database.commitNodeEdit(
        node: _node('second'),
        revision: _revision('revision-1', '{"content":"second"}'),
      ),
      throwsException,
    );

    expect(
      (await database.select(database.nodes).getSingle()).content,
      'first',
    );
    expect(await database.select(database.revisions).get(), hasLength(1));
    expect(await database.select(database.outboxEntries).get(), hasLength(1));
    expect(
      await database.select(database.derivedInvalidations).get(),
      hasLength(1),
    );
  });

  test('revision identity must match the edited node', () async {
    await expectLater(
      database.commitNodeEdit(
        node: _node('first'),
        revision: RevisionData(
          id: 'revision-1',
          entityKind: 'edge',
          entityId: 'other-node',
          payloadJson: '{}',
          createdAtMs: 1,
        ),
      ),
      throwsArgumentError,
    );
    expect(await database.select(database.nodes).get(), isEmpty);
  });

  test('revisions cannot be changed or deleted', () async {
    await database.commitNodeEdit(
      node: _node('first'),
      revision: _revision('revision-1', '{"content":"first"}'),
    );

    await expectLater(
      database.customStatement(
        "UPDATE revisions SET payload_json = '{}' WHERE id = 'revision-1'",
      ),
      throwsException,
    );
    await expectLater(
      database.customStatement("DELETE FROM revisions WHERE id = 'revision-1'"),
      throwsException,
    );
  });

  test('v3 migration preserves data and creates durable queues', () async {
    final file = File('${directory.path}/v3.db');
    await database.close();
    database = await openDatabaseWithFile(file);
    await database
        .into(database.databaseMetadata)
        .insert(
          const DatabaseMetadataData(
            key: 'existing',
            value: 'value',
            updatedAtMs: 1,
          ),
        );
    await database.close();

    final sqlite = sqlite3.open(file.path);
    sqlite.execute('DROP TABLE derived_invalidations');
    sqlite.execute('DROP TABLE outbox_entries');
    sqlite.execute('DROP TRIGGER revisions_no_update');
    sqlite.execute('DROP TRIGGER revisions_no_delete');
    sqlite.execute('PRAGMA user_version = 3');
    sqlite.close();

    database = await openDatabaseWithFile(file);
    expect(
      await database.select(database.databaseMetadata).get(),
      hasLength(1),
    );
    expect(await database.select(database.outboxEntries).get(), isEmpty);
    expect(await database.select(database.derivedInvalidations).get(), isEmpty);
  });
}

NodeData _node(String content) => NodeData(
  id: 'node-1',
  type: 'note',
  title: 'Node',
  content: content,
  attributesJson: '{}',
  createdAtMs: 1,
  updatedAtMs: 2,
);

RevisionData _revision(String id, String payload) => RevisionData(
  id: id,
  entityKind: 'node',
  entityId: 'node-1',
  payloadJson: payload,
  createdAtMs: 2,
);
