import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/widgets/work_surface.dart';
import 'package:tylog_core/models.dart';

NoteRef _note(String id, String kind) => NoteRef(
  id: id,
  path: 'notes/$id.typ',
  title: id,
  kind: kind,
  outgoingLinks: const [],
);

void main() {
  final notes = [
    _note('plain-note', 'note'),
    _note('the-project', 'project'),
    _note('ilya', 'person'),
    _note('an-article', 'article'),
  ];

  Widget surface() => MaterialApp(
    home: Scaffold(
      body: LibraryView(
        calendar: const [],
        dayMarks: (daily: <String>{}, refs: <String>{}),
        index: VaultIndex(
          notesByPath: {for (final n in notes) n.path: n},
          backlinksByTarget: const {},
          tasks: const [],
        ),
        progressByPath: const {},
        onOpenPath: (_) {},
        onOpenDay: (_) {},
        onSetTaskStatus: (_, _) async {},
        onSetReadStatus: (_, _) async {},
        onSetRelevance: (_, _) async {},
        onCreateNote: (_) {},
        onCreateEntity: () {},
        onImportMarkdownArticles: () async {},
        onReadPath: (_) {},
        onDeleteArticle: (_) async {},
      ),
    ),
  );

  testWidgets('one Notes tab lists notes, projects, and entities together', (
    tester,
  ) async {
    await tester.pumpWidget(surface());
    await tester.pumpAndSettle();

    // The old silo tabs are gone…
    expect(find.text('Projects'), findsNothing);
    expect(find.text('Entities'), findsNothing);
    // …and their contents live in the default Notes list.
    expect(find.text('plain-note'), findsOneWidget);
    expect(find.text('the-project'), findsOneWidget);
    expect(find.text('ilya'), findsOneWidget);
    // Articles keep their own shelf; the unified list does not double them.
    expect(find.text('an-article'), findsNothing);
  });

  testWidgets('kind chips filter the unified list', (tester) async {
    await tester.pumpWidget(surface());
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilterChip, 'person'));
    await tester.pumpAndSettle();
    expect(find.text('ilya'), findsOneWidget);
    expect(find.text('plain-note'), findsNothing);
    expect(find.text('the-project'), findsNothing);

    // Tapping again clears the filter.
    await tester.tap(find.widgetWithText(FilterChip, 'person'));
    await tester.pumpAndSettle();
    expect(find.text('plain-note'), findsOneWidget);
  });
}
