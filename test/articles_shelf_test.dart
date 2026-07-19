import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/models.dart';
import 'package:tylog/widgets/property_select_chip.dart';
import 'package:tylog/widgets/work_surface.dart';

void main() {
  group('articleStatusStage', () {
    test('folds legacy and custom status values onto the five stages', () {
      expect(articleStatusStage(null), 'unread');
      expect(articleStatusStage(''), 'unread');
      expect(articleStatusStage('processed'), 'unread'); // import default
      expect(articleStatusStage('skimmed'), 'skimmed');
      expect(articleStatusStage('reading'), 'read'); // legacy in-progress
      expect(articleStatusStage('read'), 'read');
      expect(articleStatusStage('summarized'), 'extracted'); // custom
      expect(articleStatusStage('extracted'), 'extracted');
      expect(articleStatusStage('cited'), 'cited');
    });
  });

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
  // `summarized` is a custom extraction value → maps to the Extracted stage.
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

    // 5-stage pipeline chips with counts from the three articles:
    // processed→Unread, reading→Read, summarized→Extracted.
    expect(find.text('All · 3'), findsOneWidget);
    expect(find.text('Unread · 1'), findsOneWidget);
    expect(find.text('Skimmed · 0'), findsOneWidget);
    expect(find.text('Read · 1'), findsOneWidget);
    expect(find.text('Extracted · 1'), findsOneWidget);
    expect(find.text('Cited · 0'), findsOneWidget);
    // Per-row pickers show the stage label, never the raw stored status value.
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

    // Unread filter hides everything but the unread article.
    await tester.tap(find.text('Unread · 1'));
    await tester.pumpAndSettle();
    expect(find.text('Fresh'), findsOneWidget);
    expect(find.text('Done'), findsNothing);
  });
}
