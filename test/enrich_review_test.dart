import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/widgets/enrich_review.dart';
import 'package:tylog_core/enrich.dart';
import 'package:tylog_core/tylog_core.dart';

void main() {
  const mention = EnrichMention(surface: 'Alex', type: 'person', line: 1);
  const first = NoteRef(
    id: 'a',
    path: 'a.typ',
    title: 'Alex A',
    kind: 'person',
    outgoingLinks: [],
  );
  const second = NoteRef(
    id: 'b',
    path: 'b.typ',
    title: 'Alex B',
    kind: 'person',
    outgoingLinks: [],
  );
  const other = NoteRef(
    id: 'c',
    path: 'c.typ',
    title: 'Charlie',
    outgoingLinks: [],
  );
  const decision = EnrichDecision(mention, EnrichStatus.review, [
    EnrichCandidate(first, 1, strong: false, lastSeenDay: "2026-10-20"),
    EnrichCandidate(second, .5, strong: false),
  ]);

  Future<void> showReview(
    WidgetTester tester,
    void Function(NoteRef) accepted,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EnrichReview(
            decisions: const [decision],
            pages: const [first, second, other],
            onAccept: (_, target) => accepted(target),
            onReject: (_, _) {},
            onCreate: (_) {},
            onIgnore: (_) {},
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('enrich-review-Alex')));
    await tester.pumpAndSettle();
  }

  testWidgets('shows candidate kind and last seen', (tester) async {
    await showReview(tester, (_) {});
    expect(find.text('Last seen 2026-10-20'), findsOneWidget);
    expect(
      find.descendant(
        of: find.widgetWithText(ListTile, 'Alex A'),
        matching: find.byIcon(Icons.person_outline),
      ),
      findsOneWidget,
    );
  });

  testWidgets('chooses a lower ranked candidate', (tester) async {
    NoteRef? accepted;
    await showReview(tester, (target) => accepted = target);
    await tester.tap(find.text('Alex B'));
    await tester.pumpAndSettle();
    expect(accepted, second);
  });

  testWidgets('searches and chooses another page', (tester) async {
    NoteRef? accepted;
    await showReview(tester, (target) => accepted = target);
    await tester.tap(find.text('Other page…'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Charlie');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, 'Charlie'));
    await tester.pumpAndSettle();
    expect(accepted, other);
  });

  testWidgets('empty page search explains the state and returns to choices', (
    tester,
  ) async {
    await showReview(tester, (_) {});
    await tester.tap(find.text('Other page…'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'no matching page');
    await tester.pumpAndSettle();
    expect(find.text('No matching pages'), findsOneWidget);
    await tester.tap(find.byTooltip('Back to suggestions'));
    await tester.pumpAndSettle();
    expect(find.text('Alex A'), findsOneWidget);
    expect(find.text('Not a person/ignore'), findsOneWidget);
  });
}
