import 'package:drift/native.dart';
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
    },
  );
}
