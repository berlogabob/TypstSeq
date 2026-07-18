import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/models.dart';
import 'package:tylog/widgets/work_surface.dart';

void main() {
  const unread = NoteRef(
    id: 'a1',
    path: 'articles/Fresh.typ',
    title: 'Fresh',
    kind: 'article',
    outgoingLinks: [],
    tags: ['ai'],
    properties: {'status': 'processed'},
    modifiedMillis: 3000,
  );
  const reading = NoteRef(
    id: 'a2',
    path: 'articles/Halfway.typ',
    title: 'Halfway',
    kind: 'article',
    outgoingLinks: [],
    tags: ['ai'],
    properties: {'status': 'reading'},
    modifiedMillis: 2000,
  );
  // Custom status values beyond read/reading/unread count as read.
  const summarized = NoteRef(
    id: 'a3',
    path: 'articles/Done.typ',
    title: 'Done',
    kind: 'article',
    outgoingLinks: [],
    properties: {'status': 'summarized'},
    modifiedMillis: 1000,
  );
  const plainNote = NoteRef(
    id: 'n1',
    path: 'notes/Not an article.typ',
    title: 'Not an article',
    kind: 'note',
    outgoingLinks: [],
  );

  Widget shelf() => MaterialApp(
    home: Scaffold(
      body: LibraryView(
        index: VaultIndex(
          notesByPath: {
            for (final n in [unread, reading, summarized, plainNote]) n.path: n,
          },
          backlinksByTarget: const {},
          tasks: const [],
        ),
        progressByPath: const {'articles/Halfway.typ': 0.4},
        onOpenPath: (_) {},
        onOpenDay: (_) {},
        onSetTaskStatus: (_, _) async {},
        onSetReadStatus: (_, _) async {},
        onCreateNote: (_) {},
        onCreateEntity: () {},
        onImportMarkdownArticles: () async {},
        onReadPath: (_) {},
        onDeleteArticle: (_) async {},
      ),
    ),
  );

  testWidgets('articles shelf: counts, recent order, filter, resume card', (
    tester,
  ) async {
    await tester.pumpWidget(shelf());
    await tester.tap(find.text('Articles'));
    await tester.pumpAndSettle();

    // Status chips with counts from the three articles only.
    expect(find.text('All · 3'), findsOneWidget);
    expect(find.text('Inbox · 1'), findsOneWidget);
    expect(find.text('Reading · 1'), findsOneWidget);
    expect(find.text('Read · 1'), findsOneWidget);
    expect(find.text('Inbox'), findsOneWidget);
    expect(find.text('Reading'), findsOneWidget);
    expect(find.text('Read'), findsOneWidget);
    expect(find.text('processed'), findsNothing);
    expect(find.text('summarized'), findsNothing);

    // Default sort is recently modified, not alphabetical/path order.
    final freshY = tester.getTopLeft(find.text('Fresh')).dy;
    final halfwayY = tester.getTopLeft(find.text('Halfway')).dy;
    final doneY = tester.getTopLeft(find.text('Done')).dy;
    expect(freshY, lessThan(halfwayY));
    expect(halfwayY, lessThan(doneY));

    // In-progress article gets the resume card with its percentage.
    expect(find.text('Continue reading · Halfway'), findsOneWidget);
    expect(find.text('40%'), findsWidgets);

    // Inbox filter hides everything but the unread article.
    await tester.tap(find.text('Inbox · 1'));
    await tester.pumpAndSettle();
    expect(find.text('Fresh'), findsOneWidget);
    expect(find.text('Done'), findsNothing);
  });
}
