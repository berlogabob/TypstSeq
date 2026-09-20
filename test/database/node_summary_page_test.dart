import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/database/tylog_database.dart';

void main() {
  test(
    'node summaries use a bounded keyset page and completion marker',
    () async {
      final database = TyLogDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      for (final id in ['a', 'b', 'c']) {
        await database.commitNodeEdit(
          node: NodeData(
            id: id,
            type: id == 'b' ? 'project' : 'note',
            title: id.toUpperCase(),
            content: 'large content omitted from summary',
            attributesJson: '{"path":"notes/$id.typ"}',
            createdAtMs: 1,
            updatedAtMs: 1,
          ),
          revision: RevisionData(
            id: 'revision-$id',
            entityKind: 'node',
            entityId: id,
            payloadJson: '{}',
            createdAtMs: 1,
          ),
        );
      }

      final first = await database.pageNodeSummaries(limit: 2);
      expect(first.nodes.map((node) => node.id), ['a', 'b']);
      expect(first.nodes.first.title, 'A');
      expect(first.nodes.first.attributesJson, contains('notes/a.typ'));
      expect(first.nextCursor, 'b');
      expect(first.complete, isFalse);

      final second = await database.pageNodeSummaries(
        afterId: first.nextCursor,
        type: 'note',
        limit: 2,
      );
      expect(second.nodes.map((node) => node.id), ['c']);
      expect(second.nextCursor, isNull);

      await database.markNodeProjectionComplete(3);
      expect((await database.pageNodeSummaries()).complete, isTrue);
    },
  );

  test('summary page rejects unbounded limits', () async {
    final database = TyLogDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    await expectLater(
      database.pageNodeSummaries(limit: 101),
      throwsArgumentError,
    );
  });
}
