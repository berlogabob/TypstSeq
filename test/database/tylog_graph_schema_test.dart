import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:tylog/database/tylog_database.dart';

void main() {
  group('TyLogDatabase Graph Schema', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = Directory.systemTemp.createTempSync('tylog_graph_test_');
    });

    tearDown(() async {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('transaction inserts source, nodes, edge, and revisions', () async {
      final file = File('${tempDir.path}/graph.db');
      final db = await openDatabaseWithFile(file);

      final sourceId = 'source_1';
      final nodeId1 = 'node_1';
      final nodeId2 = 'node_2';
      final edgeId = 'edge_1';
      final revisionId = 'rev_1';
      final now = DateTime.now().millisecondsSinceEpoch;

      await db.transaction(() async {
        // Insert source
        await db
            .into(db.sources)
            .insert(
              SourceData(
                id: sourceId,
                kind: 'article',
                title: 'Test Article',
                locator: 'http://example.com',
                attributesJson: '{"author":"test"}',
                createdAtMs: now,
                updatedAtMs: now,
              ),
            );

        // Insert two nodes
        await db
            .into(db.nodes)
            .insert(
              NodeData(
                id: nodeId1,
                type: 'concept',
                title: 'Node 1',
                content: 'Content 1',
                attributesJson: '{}',
                createdAtMs: now,
                updatedAtMs: now,
              ),
            );

        await db
            .into(db.nodes)
            .insert(
              NodeData(
                id: nodeId2,
                type: 'concept',
                title: 'Node 2',
                content: 'Content 2',
                attributesJson: '{}',
                createdAtMs: now,
                updatedAtMs: now,
              ),
            );

        // Insert edge connecting nodes
        await db
            .into(db.edges)
            .insert(
              EdgeData(
                id: edgeId,
                fromNodeId: nodeId1,
                toNodeId: nodeId2,
                type: 'related',
                attributesJson: '{}',
                createdAtMs: now,
                updatedAtMs: now,
              ),
            );

        // Insert revision
        await db
            .into(db.revisions)
            .insert(
              RevisionData(
                id: revisionId,
                entityKind: 'node',
                entityId: nodeId1,
                parentRevisionId: null,
                payloadJson: '{"version":1}',
                createdAtMs: now,
              ),
            );
      });

      // Verify all inserts persisted
      final sources = await db.select(db.sources).get();
      expect(sources.length, equals(1));
      expect(sources[0].id, equals(sourceId));

      final nodes = await db.select(db.nodes).get();
      expect(nodes.length, equals(2));

      final edges = await db.select(db.edges).get();
      expect(edges.length, equals(1));
      expect(edges[0].fromNodeId, equals(nodeId1));
      expect(edges[0].toNodeId, equals(nodeId2));

      final revisions = await db.select(db.revisions).get();
      expect(revisions.length, equals(1));
      expect(revisions[0].entityId, equals(nodeId1));

      await db.close();
    });

    test('edge with missing target node fails', () async {
      final file = File('${tempDir.path}/missing_node.db');
      final db = await openDatabaseWithFile(file);

      final nodeId = 'node_1';
      final missingNodeId = 'missing_node';
      final now = DateTime.now().millisecondsSinceEpoch;

      await db
          .into(db.nodes)
          .insert(
            NodeData(
              id: nodeId,
              type: 'concept',
              title: 'Node 1',
              content: 'Content 1',
              attributesJson: '{}',
              createdAtMs: now,
              updatedAtMs: now,
            ),
          );

      // Attempting to insert edge with missing target node should fail
      expect(
        () async => db
            .into(db.edges)
            .insert(
              EdgeData(
                id: 'edge_1',
                fromNodeId: nodeId,
                toNodeId: missingNodeId,
                type: 'related',
                attributesJson: '{}',
                createdAtMs: now,
                updatedAtMs: now,
              ),
            ),
        throwsException,
      );

      await db.close();
    });

    test('invalid JSON attributes are rejected', () async {
      final db = await openDatabaseWithFile(File('${tempDir.path}/json.db'));
      final now = DateTime.now().millisecondsSinceEpoch;

      await expectLater(
        db
            .into(db.nodes)
            .insert(
              NodeData(
                id: 'node_1',
                type: 'note',
                title: 'Node',
                content: '',
                attributesJson: '{invalid',
                createdAtMs: now,
                updatedAtMs: now,
              ),
            ),
        throwsException,
      );
      await db.close();
    });

    test('reversed temporal ranges are rejected', () async {
      final db = await openDatabaseWithFile(File('${tempDir.path}/dates.db'));

      await expectLater(
        db
            .into(db.nodes)
            .insert(
              const NodeData(
                id: 'node_1',
                type: 'event',
                title: 'Node',
                content: '',
                attributesJson: '{}',
                eventStartMs: 2,
                eventEndMs: 1,
                createdAtMs: 3,
                updatedAtMs: 3,
              ),
            ),
        throwsException,
      );
      await db.close();
    });

    test('duplicate node ID in transaction rolls back all inserts', () async {
      final file = File('${tempDir.path}/rollback.db');
      final db = await openDatabaseWithFile(file);

      final nodeId = 'node_1';
      final now = DateTime.now().millisecondsSinceEpoch;

      await expectLater(
        db.transaction(() async {
          // Insert first node
          await db
              .into(db.nodes)
              .insert(
                NodeData(
                  id: nodeId,
                  type: 'concept',
                  title: 'Node 1',
                  content: 'Content 1',
                  attributesJson: '{}',
                  createdAtMs: now,
                  updatedAtMs: now,
                ),
              );

          // Try to insert duplicate node ID - should fail
          await db
              .into(db.nodes)
              .insert(
                NodeData(
                  id: nodeId,
                  type: 'concept',
                  title: 'Node 1 Duplicate',
                  content: 'Content 1 Duplicate',
                  attributesJson: '{}',
                  createdAtMs: now,
                  updatedAtMs: now,
                ),
              );
        }),
        throwsException,
      );

      // Verify no nodes exist after rollback
      final nodes = await db.select(db.nodes).get();
      expect(nodes.length, equals(0));

      await db.close();
    });

    test('event dates distinct from created/updated timestamps', () async {
      final file = File('${tempDir.path}/event_dates.db');
      final db = await openDatabaseWithFile(file);

      final nodeId = 'node_1';
      final now = DateTime.now().millisecondsSinceEpoch;
      final eventStart = now - 86400000; // 1 day ago
      final eventEnd = now - 43200000; // 12 hours ago

      await db
          .into(db.nodes)
          .insert(
            NodeData(
              id: nodeId,
              type: 'event',
              title: 'Event Node',
              content: 'Content',
              attributesJson: '{}',
              eventStartMs: eventStart,
              eventEndMs: eventEnd,
              createdAtMs: now,
              updatedAtMs: now,
            ),
          );

      final nodes = await db.select(db.nodes).get();
      expect(nodes.length, equals(1));
      expect(nodes[0].eventStartMs, equals(eventStart));
      expect(nodes[0].eventEndMs, equals(eventEnd));
      expect(nodes[0].createdAtMs, equals(now));
      expect(nodes[0].updatedAtMs, equals(now));

      await db.close();
    });

    test('null event and valid dates are accepted', () async {
      final file = File('${tempDir.path}/null_dates.db');
      final db = await openDatabaseWithFile(file);

      final now = DateTime.now().millisecondsSinceEpoch;

      // Node with null event dates
      await db
          .into(db.nodes)
          .insert(
            NodeData(
              id: 'node_1',
              type: 'concept',
              title: 'Node',
              content: 'Content',
              attributesJson: '{}',
              eventStartMs: null,
              eventEndMs: null,
              createdAtMs: now,
              updatedAtMs: now,
            ),
          );

      // Edge with null valid dates
      await db
          .into(db.nodes)
          .insert(
            NodeData(
              id: 'node_2',
              type: 'concept',
              title: 'Node 2',
              content: 'Content',
              attributesJson: '{}',
              createdAtMs: now,
              updatedAtMs: now,
            ),
          );

      await db
          .into(db.edges)
          .insert(
            EdgeData(
              id: 'edge_1',
              fromNodeId: 'node_1',
              toNodeId: 'node_2',
              type: 'related',
              attributesJson: '{}',
              validFromMs: null,
              validToMs: null,
              createdAtMs: now,
              updatedAtMs: now,
            ),
          );

      final nodes = await db.select(db.nodes).get();
      expect(nodes.every((node) => node.eventStartMs == null), isTrue);

      final edges = await db.select(db.edges).get();
      expect(edges[0].validFromMs, isNull);
      expect(edges[0].validToMs, isNull);

      await db.close();
    });

    test('v2 database migrates to v5 preserving metadata', () async {
      final file = File('${tempDir.path}/v2_to_v5.db');

      // Create a v2 database file
      final sqlite = sqlite3.open(file.path);
      sqlite.execute('PRAGMA user_version = 2;');
      sqlite.execute('''
        CREATE TABLE database_metadata (
          key TEXT NOT NULL PRIMARY KEY,
          value TEXT NOT NULL,
          updated_at_ms INTEGER NOT NULL DEFAULT 0
        )
      ''');
      sqlite.execute('''
        INSERT INTO database_metadata (key, value, updated_at_ms)
        VALUES ('v2_key', 'v2_value', 12345)
      ''');
      sqlite.close();

      // Open with Drift to trigger migration
      final db = await openDatabaseWithFile(file);
      expect(db.schemaVersion, equals(5));

      // Verify metadata preserved
      final metadata = await db.select(db.databaseMetadata).get();
      expect(metadata.length, equals(1));
      expect(metadata[0].key, equals('v2_key'));
      expect(metadata[0].value, equals('v2_value'));
      expect(metadata[0].updatedAtMs, equals(12345));

      // Verify new tables exist
      final tables = await db.customSelect('''
        SELECT name FROM sqlite_master
        WHERE type='table' AND name IN ('nodes', 'edges', 'sources', 'revisions')
      ''').get();
      expect(tables.length, equals(4));

      final indexes = await db.customSelect('''
        SELECT name FROM sqlite_master
        WHERE type='index' AND name LIKE 'idx_%'
      ''').get();
      expect(indexes.length, equals(11));

      await db.close();
    });

    test('foreign key constraint enforced on fromNodeId', () async {
      final file = File('${tempDir.path}/fk_constraint.db');
      final db = await openDatabaseWithFile(file);

      final now = DateTime.now().millisecondsSinceEpoch;

      // Create one node
      await db
          .into(db.nodes)
          .insert(
            NodeData(
              id: 'node_1',
              type: 'concept',
              title: 'Node 1',
              content: 'Content 1',
              attributesJson: '{}',
              createdAtMs: now,
              updatedAtMs: now,
            ),
          );

      // Try to create edge with non-existent from node
      expect(
        () async => db
            .into(db.edges)
            .insert(
              EdgeData(
                id: 'edge_1',
                fromNodeId: 'nonexistent',
                toNodeId: 'node_1',
                type: 'related',
                attributesJson: '{}',
                createdAtMs: now,
                updatedAtMs: now,
              ),
            ),
        throwsException,
      );

      await db.close();
    });

    test('revision self-reference allows parent chain', () async {
      final file = File('${tempDir.path}/revision_chain.db');
      final db = await openDatabaseWithFile(file);

      final now = DateTime.now().millisecondsSinceEpoch;

      await db.transaction(() async {
        // Insert parent revision
        await db
            .into(db.revisions)
            .insert(
              RevisionData(
                id: 'rev_1',
                entityKind: 'node',
                entityId: 'node_1',
                parentRevisionId: null,
                payloadJson: '{"version":1}',
                createdAtMs: now,
              ),
            );

        // Insert child revision
        await db
            .into(db.revisions)
            .insert(
              RevisionData(
                id: 'rev_2',
                entityKind: 'node',
                entityId: 'node_1',
                parentRevisionId: 'rev_1',
                payloadJson: '{"version":2}',
                createdAtMs: now + 1000,
              ),
            );

        // Insert grandchild revision
        await db
            .into(db.revisions)
            .insert(
              RevisionData(
                id: 'rev_3',
                entityKind: 'node',
                entityId: 'node_1',
                parentRevisionId: 'rev_2',
                payloadJson: '{"version":3}',
                createdAtMs: now + 2000,
              ),
            );
      });

      final revisions = await db.select(db.revisions).get();
      expect(revisions.length, equals(3));

      final childRev = revisions.firstWhere((r) => r.id == 'rev_2');
      expect(childRev.parentRevisionId, equals('rev_1'));

      final grandchildRev = revisions.firstWhere((r) => r.id == 'rev_3');
      expect(grandchildRev.parentRevisionId, equals('rev_2'));

      await db.close();
    });
  });
}
