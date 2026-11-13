import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/widgets/enrich_review.dart';
import 'package:tylog_core/tylog_core.dart';

void main() {
  for (final scale in [1.0, 1.3]) {
    testWidgets('targets wrap without truncation at text scale $scale', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      const linked = NoteRef(
        id: 'linked',
        path: 'linked.typ',
        title: 'A very long destination title that wraps on a phone',
        kind: 'person',
        outgoingLinks: [],
      );
      const linkedEquipment = NoteRef(
        id: 'equipment',
        path: 'equipment.typ',
        title: 'QUEST 3 [1]',
        kind: 'equipment',
        outgoingLinks: [],
        properties: {'color': 'yellow'},
      );
      const ambiguousA = NoteRef(
        id: 'ambiguous-a',
        path: 'ambiguous-a.typ',
        title: 'Ambiguous candidate one',
        outgoingLinks: [],
      );
      const ambiguousB = NoteRef(
        id: 'ambiguous-b',
        path: 'ambiguous-b.typ',
        title: 'Ambiguous candidate two',
        outgoingLinks: [],
      );
      const proposed = EnrichMention(
        surface: 'A very long proposed surface that wraps',
        type: 'person',
        line: 1,
      );
      const ambiguous = EnrichMention(
        surface: 'A very long ambiguous surface that wraps',
        type: 'topic',
        line: 1,
      );
      const proposedDecision = EnrichDecision(
        proposed,
        EnrichStatus.propose,
        [],
      );
      const ambiguousDecision = EnrichDecision(ambiguous, EnrichStatus.review, [
        EnrichCandidate(ambiguousA, .8, strong: false),
        EnrichCandidate(ambiguousB, .7, strong: false),
      ], choose: true);
      const willLink = EnrichDecision(
        EnrichMention(surface: 'José Graça', type: 'person', line: 1),
        EnrichStatus.review,
        [EnrichCandidate(linked, 1, strong: true)],
      );
      const loan = EnrichLoanOffer(
        line: 1,
        text:
            'José Graça yellow Quest 3 A very long ambiguous surface that wraps A very long proposed surface that wraps',
        ledgerSurface: 'equipment',
        equipment: [linkedEquipment],
      );

      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: Scaffold(
            body: ListView(
              children: [
                EnrichReview(
                  source:
                      'José Graça yellow Quest 3 A very long ambiguous surface that wraps A very long proposed surface that wraps',
                  pages: const [linkedEquipment],
                  decisions: const [
                    willLink,
                    ambiguousDecision,
                    proposedDecision,
                  ],
                  loans: [loan],
                  onAccept: (_, _) {},
                  onReject: (_, _) {},
                  onCreate: (_) {},
                  onIgnore: (_) {},
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('QUEST 3 unit 1 · yellow'), findsOneWidget);

      final rowSizes = [
        tester
            .getSize(find.byKey(const ValueKey('enrich-row-1-QUEST 3 [1]')))
            .height,
        for (final surface in [
          'José Graça',
          'A very long ambiguous surface that wraps',
          'A very long proposed surface that wraps',
        ])
          tester.getSize(find.byKey(ValueKey('enrich-row-1-$surface'))).height,
      ];
      expect(rowSizes, everyElement(greaterThanOrEqualTo(48)));
      expect(find.text(linked.title), findsOneWidget);
      final equipmentRow = find.byKey(
        const ValueKey('enrich-row-1-QUEST 3 [1]'),
      );
      expect(
        tester.getTopLeft(find.text('QUEST 3 unit 1 · yellow')).dy,
        greaterThan(tester.getTopLeft(equipmentRow).dy),
      );
      final rows =
          [
                'QUEST 3 [1]',
                'José Graça',
                'A very long ambiguous surface that wraps',
                'A very long proposed surface that wraps',
              ]
              .map((surface) => find.byKey(ValueKey('enrich-row-1-$surface')))
              .toList()
            ..sort(
              (a, b) =>
                  tester.getTopLeft(a).dy.compareTo(tester.getTopLeft(b).dy),
            );
      for (var i = 1; i < rows.length; i++) {
        expect(
          tester.getTopLeft(rows[i]).dy,
          tester.getBottomLeft(rows[i - 1]).dy,
        );
      }
      expect(find.byType(Scrollable), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
  test('equipment short target retains unit and omits the tag', () {
    const target = NoteRef(
      id: 'TL-0102',
      path: 'item.typ',
      title: 'QUEST 3 unit 1 TL-0102',
      kind: 'equipment',
      outgoingLinks: [],
      properties: {'item': 'Quest 3'},
    );
    expect(enrichShortTarget('yellow Quest 3', target), 'unit 1');
    expect(enrichShortTarget('headset', target), 'QUEST 3 unit 1');
  });

  test('short target removes the repeated item name', () {
    const target = NoteRef(
      id: 'TL-0102',
      path: 'item.typ',
      title: 'QUEST 3 [1] TL-0102',
      outgoingLinks: [],
    );
    expect(enrichShortTarget('yellow QUEST 3 [1]', target), 'TL-0102');
  });
}
