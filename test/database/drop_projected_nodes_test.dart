import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/database/tylog_database.dart';

NodeData _node(String id) => NodeData(
  id: id,
  type: 'note',
  title: id,
  content: '',
  attributesJson: '{}',
  createdAtMs: 1,
  updatedAtMs: 1,
);

void main() {
  test('cleanup keeps nodes that edges or import mappings still use', () async {
    final db = TyLogDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db.projectNodes([
      _node('dup-free'),
      _node('dup-edge'),
      _node('dup-mapped'),
      _node('other'),
    ]);
    await db.into(db.edges).insert(
      const EdgeData(
        id: 'e1',
        fromNodeId: 'other',
        toNodeId: 'dup-edge',
        type: 'links',
        attributesJson: '{}',
        createdAtMs: 1,
        updatedAtMs: 1,
      ),
    );
    await db.into(db.importJobs).insert(
      const ImportJobData(
        id: 'job',
        sourceKind: 'logseq',
        sourceFingerprint: 'sha',
        status: 'completed',
        totalCount: 1,
        completedCount: 1,
        createdAtMs: 1,
        updatedAtMs: 1,
        errorJson: '{}',
      ),
    );
    await db.into(db.importItems).insert(
      const ImportItemData(
        jobId: 'job',
        sourcePath: 'pages/x.md',
        sourceSha256: 'x',
        state: 'written',
        targetNodeId: 'dup-mapped',
        targetPath: 'notes/x.typ',
        errorJson: '{}',
        updatedAtMs: 1,
      ),
    );

    await db.dropProjectedNodes(['dup-free', 'dup-edge', 'dup-mapped']);

    final ids = (await db.select(db.nodes).get()).map((n) => n.id).toSet();
    expect(ids, {'dup-edge', 'dup-mapped', 'other'});
    expect(await db.searchNodeIds('dup'), isNot(contains('dup-free')));
  });
}
