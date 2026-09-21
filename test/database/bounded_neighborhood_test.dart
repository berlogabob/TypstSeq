import 'package:drift/native.dart';
import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/database/tylog_database.dart';

void main() {
  test(
    'bounded neighborhood terminates on cycles and returns stable depths',
    () async {
      final db = TyLogDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      for (final id in ['a', 'b', 'c']) {
        await db
            .into(db.nodes)
            .insert(
              NodesCompanion.insert(
                id: id,
                type: 'note',
                title: id,
                content: id,
                createdAtMs: 1,
                updatedAtMs: 1,
              ),
            );
      }
      for (final edge in [
        ('ab', 'a', 'b'),
        ('bc', 'b', 'c'),
        ('ca', 'c', 'a'),
      ]) {
        await db
            .into(db.edges)
            .insert(
              EdgesCompanion.insert(
                id: edge.$1,
                fromNodeId: edge.$2,
                toNodeId: edge.$3,
                type: 'links',
                createdAtMs: 1,
                updatedAtMs: 1,
              ),
            );
      }
      final result = await db.boundedNeighborhood('a', maxDepth: 2);
      expect(result.map((row) => '${row.id}:${row.depth}'), [
        'a:0',
        'b:1',
        'c:1',
      ]);
      await db.deleteEdge('ca');
      expect((await db.select(db.edges).get()).map((edge) => edge.id), [
        'ab',
        'bc',
      ]);
    },
  );

  test(
    'caps high fanout deterministically and rejects missing seeds',
    () async {
      final db = TyLogDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      for (final id in [
        'root',
        ...List.generate(250, (i) => 'n${i.toString().padLeft(3, '0')}'),
      ]) {
        await db
            .into(db.nodes)
            .insert(
              NodesCompanion.insert(
                id: id,
                type: 'note',
                title: id,
                content: id,
                createdAtMs: 1,
                updatedAtMs: 1,
              ),
            );
      }
      for (var i = 0; i < 250; i++) {
        await db
            .into(db.edges)
            .insert(
              EdgesCompanion.insert(
                id: 'e${i.toString().padLeft(3, '0')}',
                fromNodeId: 'root',
                toNodeId: 'n${i.toString().padLeft(3, '0')}',
                type: 'links',
                createdAtMs: 1,
                updatedAtMs: 1,
              ),
            );
      }
      final result = await db.boundedNeighborhood('root', maxDepth: 1);
      expect(result, hasLength(200));
      expect(result.first.id, 'root');
      expect(result.last.id, 'n198');
      expect(await db.boundedNeighborhood('missing'), isEmpty);
    },
  );

  test('validates traversal bounds', () async {
    final db = TyLogDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    expect(
      () => db.boundedNeighborhood('x', maxDepth: 11),
      throwsArgumentError,
    );
    expect(
      () => db.boundedNeighborhood('x', maxNodes: 201),
      throwsArgumentError,
    );
    expect(
      () => db.boundedNeighborhood('x', maxEdges: 501),
      throwsArgumentError,
    );
  });

  test('graph edge lookup keeps both endpoint indexes available', () async {
    final db = TyLogDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final plan = await db
        .customSelect(
          'EXPLAIN QUERY PLAN SELECT DISTINCT id FROM edges '
          'WHERE from_node_id IN (?) OR to_node_id IN (?) '
          'ORDER BY id LIMIT ?',
          variables: [
            Variable.withString('root'),
            Variable.withString('root'),
            Variable.withInt(200),
          ],
        )
        .get();
    final details = plan.map((row) => row.read<String>('detail')).join('\n');
    expect(details, contains('idx_edges_from_node_type'));
    expect(details, contains('idx_edges_to_node_type'));
  });
}
