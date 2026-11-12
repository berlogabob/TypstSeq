import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/widgets/enrich_review.dart';
import 'package:tylog_core/tylog_core.dart';

void main() {
  const offer = EnrichLoanOffer(
    line: 3,
    text: 'Borrowed equipment',
    ledgerSurface: 'Borrowed equipment',
    equipment: [
      NoteRef(
        id: 'a',
        path: 'a.typ',
        title: 'Camera',
        kind: 'equipment',
        outgoingLinks: [],
      ),
      NoteRef(
        id: 'b',
        path: 'b.typ',
        title: 'Tripod',
        kind: 'equipment',
        outgoingLinks: [],
      ),
    ],
  );

  testWidgets('loan chip accepts and rejects the offer', (tester) async {
    EnrichLoanOffer? accepted;
    EnrichLoanOffer? rejected;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EnrichReview(
            decisions: const [],
            loans: const [offer],
            onAcceptLoan: (value) => accepted = value,
            onRejectLoan: (value) => rejected = value,
            onAccept: (_, _) {},
            onReject: (_, _) {},
            onCreate: (_) {},
            onIgnore: (_) {},
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Track as loan: Camera, Tripod'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('enrich-loan-3')));
    await tester.pump(const Duration(milliseconds: 200));
    expect(accepted, same(offer));
    await tester.tap(find.byTooltip('Not a loan'));
    await tester.pump(const Duration(milliseconds: 200));
    expect(rejected, same(offer));
  });

  testWidgets('review chip says what tapping does, with a short target', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const target = NoteRef(
      id: 'TL-0103',
      path: 'b.typ',
      title: 'Soldering station A TL-0103',
      kind: 'equipment',
      outgoingLinks: [],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EnrichReview(
            decisions: [
              EnrichDecision(
                const EnrichMention(
                  surface: 'Soldering station A',
                  type: 'equipment',
                  line: 1,
                ),
                EnrichStatus.review,
                [EnrichCandidate(target, 0, strong: false)],
              ),
            ],
            onAccept: (_, _) {},
            onReject: (_, _) {},
            onCreate: (_) {},
            onIgnore: (_) {},
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Link \u201cSoldering station A\u201d'), findsOneWidget);
    expect(find.text(' \u2192 TL-0103'), findsOneWidget);
    expect(find.byIcon(Icons.add_link), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty review renders no suggestions', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EnrichReview(
            decisions: const [],
            onAccept: (_, _) {},
            onReject: (_, _) {},
            onCreate: (_) {},
            onIgnore: (_) {},
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byType(InputChip), findsNothing);
    expect(find.text('Mentions'), findsNothing);
  });
}
