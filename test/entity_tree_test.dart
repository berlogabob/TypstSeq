import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/widgets/entity_tree.dart';
import 'package:tylog_core/models.dart';

NoteRef note(String id, [List<String> parents = const []]) => NoteRef(
  id: id,
  path: '$id.typ',
  title: id,
  kind: 'person',
  partOf: parents,
  outgoingLinks: const [],
);

void main() {
  test(
    'roots, multiple parents, missing parents, cycles and filtered ancestors',
    () {
      final notes = [
        note('a'),
        note('b'),
        note('child', ['a', 'b']),
        note('orphan', ['missing']),
        note('x', ['y']),
        note('y', ['x']),
      ];
      final tree = buildEntityTree(notes, notes.map((n) => n.path).toSet());
      expect(tree.map((n) => n.note.id), ['a', 'b', 'orphan', 'x']);
      expect(tree[0].children.single.note.id, 'child');
      expect(tree[1].children.single.note.id, 'child');
      expect(tree.last.children.single.note.id, 'y');
      expect(tree.last.children.single.children, isEmpty);
      final filtered = buildEntityTree(notes, {'child.typ'});
      expect(filtered.map((n) => n.note.id), ['a', 'b']);
      expect(
        filtered.every((n) => n.children.single.note.id == 'child'),
        isTrue,
      );
    },
  );

  testWidgets('tree expands and opens a child', (tester) async {
    final notes = [
      note('parent'),
      note('child', ['parent']),
    ];
    String? opened;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: EntityTree(
              nodes: buildEntityTree(notes, notes.map((n) => n.path).toSet()),
              onOpen: (path) => opened = path,
            ),
          ),
        ),
      ),
    );
    expect(find.text('child'), findsNothing);
    await tester.tap(find.byIcon(Icons.expand_more));
    await tester.pumpAndSettle();
    await tester.tap(find.text('child'));
    expect(opened, 'child.typ');
  });
}
