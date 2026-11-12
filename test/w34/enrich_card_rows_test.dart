import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/widgets/enrich_review.dart';
import 'package:tylog_core/tylog_core.dart';

void main() {
  testWidgets('rows in one card have equal heights across states', (
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
    const proposedDecision = EnrichDecision(proposed, EnrichStatus.propose, []);
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

    expect(find.text('QUEST 3 [1] · yellow'), findsOneWidget);

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
    expect(rowSizes, everyElement(48));
  });
}
