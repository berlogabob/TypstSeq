import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/models.dart';
import 'package:tylog/widgets/date_format.dart';
import 'package:tylog/widgets/work_surface.dart';

void main() {
  test('compact dates use locale names and include only past/future years', () {
    final day = DateTime(2026, 10, 5);
    expect(compactHumanDate(day, now: day, locale: 'en'), 'Mon 5 Oct');
    expect(
      compactHumanDate(day, now: DateTime(2027), locale: 'en'),
      'Mon 5 Oct 2026',
    );
    expect(compactHumanDate(day, now: day, locale: 'de'), 'Mo. 5 Okt.');
    expect(compactHumanDate(day, now: day, locale: 'unsupported'), 'Mon 5 Oct');
  });

  testWidgets(
    'date title fits alongside day navigation and app actions at 1.3',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 780));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      for (final year in [DateTime.now().year, DateTime.now().year - 1]) {
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(1.3)),
              child: child!,
            ),
            home: Scaffold(
              appBar: AppBar(
                title: Row(
                  children: [
                    IconButton(
                      onPressed: () {},
                      icon: const Icon(Icons.chevron_left),
                    ),
                    Flexible(
                      child: CompactDateTitle(
                        day: DateTime(year, 10, 5),
                        dirty: true,
                      ),
                    ),
                    IconButton(
                      onPressed: () {},
                      icon: const Icon(Icons.chevron_right),
                    ),
                  ],
                ),
                actions: [
                  for (var i = 0; i < 3; i++)
                    IconButton(
                      onPressed: () {},
                      icon: const Icon(Icons.more_vert),
                    ),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final title = find.descendant(
          of: find.byType(CompactDateTitle),
          matching: find.byType(Text),
        );
        expect(
          tester.widget<Text>(title).overflow,
          isNot(TextOverflow.ellipsis),
        );
        expect(
          tester.widget<FittedBox>(find.byType(FittedBox).first).fit,
          BoxFit.scaleDown,
        );
      }
    },
  );

  testWidgets(
    'screenshots grid keeps readable titles and one filter row at 360dp / 1.3',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 780));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final notes = [
        const NoteRef(
          id: 'one',
          path: 'screenshots/one.typ',
          title: 'Screenshot_20261005.png',
          kind: 'screenshot',
          outgoingLinks: [],
          screenshotDescription: 'Useful Flutter layout. More details here.',
          properties: {
            'captured_at': '2026-10-05T09:07:00',
            'source_app': 'Browser',
          },
        ),
        const NoteRef(
          id: 'two',
          path: 'screenshots/two.typ',
          title: 'capture.JPG',
          kind: 'screenshot',
          outgoingLinks: [],
          properties: {
            'captured_at': '2026-10-05T10:08:00',
            'source_app': 'Browser',
          },
        ),
        const NoteRef(
          id: 'three',
          path: 'screenshots/three.typ',
          title: 'My chosen title',
          kind: 'screenshot',
          outgoingLinks: [],
          properties: {'source_app': 'Browser'},
        ),
      ];
      final opened = <String>[];
      final deleted = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.3)),
            child: child!,
          ),
          home: Scaffold(
            body: WorkSurface(
              child: LibraryView(
                initialTab: 2,
                index: VaultIndex(
                  notesByPath: {for (final note in notes) note.path: note},
                  backlinksByTarget: const {},
                ),
                calendar: const [],
                dayMarks: (daily: <String>{}, refs: <String>{}),
                progressByPath: const {},
                onOpenPath: opened.add,
                onOpenDay: (_) {},
                onSetTaskStatus: (_, _) async {},
                onSetReadStatus: (_, _) async {},
                onSetRelevance: (_, _) async {},
                onCreateNote: (_) {},
                onCreateEntity: () {},
                onImportMarkdownArticles: () async {},
                onReadPath: opened.add,
                onDeleteArticle: (note) async => deleted.add(note.path),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(SliverGrid), findsOneWidget);
      expect(find.text('Screenshot_20261005.png'), findsNothing);
      expect(find.text('Useful Flutter layout.'), findsOneWidget);
      expect(find.text('Screenshot'), findsNothing);
      expect(find.text('10:08 · Browser'), findsOneWidget);
      final title = find.text('Useful Flutter layout.');
      expect(tester.getSize(title).width, greaterThan(120));
      final text = tester.widget<Text>(title);
      expect(text.maxLines, 2);
      expect(text.overflow, TextOverflow.ellipsis);
      final paragraph = tester.renderObject<RenderParagraph>(title);
      final boxes = paragraph.getBoxesForSelection(
        const TextSelection(baseOffset: 0, extentOffset: 6),
      );
      expect(
        boxes.map((box) => box.top).toSet().length,
        1,
        reason: 'Useful must fit on one line',
      );
      final filters = find.byKey(const Key('screenshots-filters'));
      final chipFinder = find.descendant(
        of: filters,
        matching: find.byType(ChoiceChip),
      );
      final tops = chipFinder
          .evaluate()
          .map((e) => tester.getTopLeft(find.byWidget(e.widget)).dy)
          .toSet();
      expect(tops.length, 1);
      await tester.drag(filters, const Offset(-1000, 0));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.widgetWithText(ChoiceChip, 'High'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, 'High'));
      await tester.pumpAndSettle();
      expect(find.text('Nothing matches'), findsOneWidget);
      await tester.ensureVisible(
        find.widgetWithText(ChoiceChip, 'Any relevance'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, 'Any relevance'));
      await tester.pumpAndSettle();
      await tester.tap(title);
      expect(opened, [notes.first.path]);
      await tester.longPress(title);
      await tester.pumpAndSettle();
      expect(find.text('Delete screenshot…'), findsOneWidget);
      await tester.tap(find.text('Delete screenshot…'));
      await tester.pumpAndSettle();
      expect(deleted, [notes.first.path]);
      expect(tester.takeException(), isNull);
    },
  );
}
