import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/widgets/enrich_review.dart';
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
          body: ListView(
            children: [
              EnrichReview(
                source: 'Alex',
                decisions: const [decision],
                pages: const [first, second, other],
                onAccept: (_, target) => accepted(target),
                onReject: (_, _) {},
                onCreate: (_) {},
                onIgnore: (_) {},
              ),
            ],
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('enrich-row-1-Alex')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byKey(const ValueKey('enrich-menu-other')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
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
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(accepted, second);
  });

  testWidgets('searches and chooses another page', (tester) async {
    NoteRef? accepted;
    await showReview(tester, (target) => accepted = target);
    await tester.tap(find.text('Other page…'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.enterText(find.byType(TextField), 'Charlie');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.widgetWithText(ListTile, 'Charlie'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(accepted, other);
  });

  testWidgets('empty page search explains the state and returns to choices', (
    tester,
  ) async {
    await showReview(tester, (_) {});
    await tester.tap(find.text('Other page…'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.enterText(find.byType(TextField), 'no matching page');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('No matching pages'), findsOneWidget);
    await tester.tap(find.byTooltip('Back to suggestions'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.widgetWithText(ListTile, 'Alex A'), findsOneWidget);
    expect(find.text('Not a person/ignore'), findsOneWidget);
  });

  testWidgets('shared equipment name shows one chooser with only its units', (
    tester,
  ) async {
    const quest = EnrichMention(
      surface: 'Quest 3',
      type: 'equipment',
      line: 1,
      candidateIds: ['q1', 'q2'],
    );
    const q1 = NoteRef(
      id: 'q1',
      path: 'q1.typ',
      title: 'QUEST 3 [1]',
      kind: 'equipment',
      outgoingLinks: [],
      properties: {'color': 'yellow'},
    );
    const q2 = NoteRef(
      id: 'q2',
      path: 'q2.typ',
      title: 'QUEST 3 [2]',
      kind: 'equipment',
      outgoingLinks: [],
      properties: {'color': 'blue'},
    );
    NoteRef? accepted;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            children: [
              EnrichReview(
                source: 'Quest 3',
                decisions: const [
                  EnrichDecision(quest, EnrichStatus.review, [
                    EnrichCandidate(q1, 0, strong: false),
                    EnrichCandidate(q2, 0, strong: false),
                  ], choose: true),
                ],
                pages: const [q1, q2, other],
                onAccept: (_, target) => accepted = target,
                onReject: (_, _) {},
                onCreate: (_) {},
                onIgnore: (_) {},
              ),
            ],
          ),
        ),
      ),
    );
    expect(find.text('choose…'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('enrich-row-1-Quest 3')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('QUEST 3 [1] \u00b7 yellow'), findsOneWidget);
    expect(find.text('QUEST 3 [2] \u00b7 blue'), findsOneWidget);
    expect(find.text('Charlie'), findsNothing);
    expect(find.text('Other page…'), findsNothing);
    expect(find.text('New page'), findsNothing);
    await tester.tap(find.text('QUEST 3 [2] \u00b7 blue'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(accepted, q2);
  });
}
