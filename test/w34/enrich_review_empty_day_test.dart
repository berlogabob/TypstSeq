import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/widgets/enrich_review.dart';
import 'package:tylog_core/tylog_core.dart';

void main() {
  testWidgets('visible cards show the review count and Accept all', (
    tester,
  ) async {
    const mention = EnrichMention(surface: 'Ada', type: 'person', line: 1);
    const page = NoteRef(
      id: 'ada',
      path: 'people/ada.typ',
      title: 'Ada',
      kind: 'person',
      outgoingLinks: [],
    );
    const decision = EnrichDecision(mention, EnrichStatus.review, [
      EnrichCandidate(page, 1, strong: true),
    ]);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            children: [
              EnrichReview(
                dayLabel: 'Tue 3 Nov',
                source: 'Ada',
                decisions: const [decision],
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
    expect(find.text('Tue 3 Nov · 1 line to review'), findsOneWidget);
    expect(find.byKey(const ValueKey('enrich-accept-all')), findsOneWidget);
  });

  testWidgets('tag-only day shows a date header without a review count', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            children: [
              EnrichReview(
                dayLabel: 'Tue 3 Nov',
                decisions: const [],
                tags: const ['design'],
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
    expect(find.text('Tue 3 Nov'), findsOneWidget);
    expect(find.textContaining('lines to review'), findsNothing);
    expect(find.text('Tags'), findsOneWidget);
    expect(find.byKey(const ValueKey('enrich-accept-all')), findsNothing);
  });

  testWidgets('empty day collapses to zero height', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              EnrichReview(
                dayLabel: 'Tue 3 Nov',
                decisions: const [],
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
    expect(find.text('Tue 3 Nov'), findsNothing);
    expect(tester.getSize(find.byType(EnrichReview)).height, 0);
  });
}
