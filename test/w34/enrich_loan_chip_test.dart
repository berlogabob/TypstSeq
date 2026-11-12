import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tylog/widgets/enrich_review.dart';
import 'package:tylog_core/tylog_core.dart';

void main() {
  const camera = NoteRef(
    id: 'camera',
    path: 'camera.typ',
    title: 'Camera',
    kind: 'equipment',
    outgoingLinks: [],
  );
  const tripod = NoteRef(
    id: 'tripod',
    path: 'tripod.typ',
    title: 'Tripod',
    kind: 'equipment',
    outgoingLinks: [],
  );
  const a = EnrichMention(surface: 'Camera', type: 'equipment', line: 1);
  const b = EnrichMention(surface: 'Tripod', type: 'equipment', line: 1);
  const c = EnrichMention(surface: 'Choice', type: 'equipment', line: 3);
  const decisions = [
    EnrichDecision(a, EnrichStatus.review, [
      EnrichCandidate(camera, 1, strong: true),
    ]),
    EnrichDecision(b, EnrichStatus.review, [
      EnrichCandidate(tripod, 1, strong: true),
    ]),
    EnrichDecision(c, EnrichStatus.review, [
      EnrichCandidate(camera, 1, strong: false),
      EnrichCandidate(tripod, 1, strong: false),
    ], choose: true),
  ];
  const firstLoan = EnrichLoanOffer(
    line: 1,
    text: 'Camera and Tripod',
    ledgerSurface: 'Camera and Tripod',
    equipment: [camera, tripod],
  );
  const secondLoan = EnrichLoanOffer(
    line: 2,
    text: 'Another loan',
    ledgerSurface: 'Another loan',
    equipment: [camera],
  );
  const source = 'Camera and Tripod\nAnother loan\nChoice';
  const conflict = TaskRef(
    id: 'loan',
    notePath: 'a.typ',
    text: 'Loan',
    clocked: [ClockEntry(start: '2026-01-01T10:00:00Z')],
    properties: {'loan': true, 'borrower': 'Sam'},
  );

  Future<void> mount(
    WidgetTester tester, {
    List<String>? events,
    Set<String> skipped = const {},
    ValueChanged<String>? onSkip,
    Future<void> Function(Future<void> Function())? batch,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
            child: ListView(
              children: [
                EnrichReview(
                  source: source,
                  dayLabel: 'Wednesday 12 Nov',
                  decisions: decisions,
                  loans: const [firstLoan, secondLoan],
                  openLoans: const {
                    'camera': [conflict],
                  },
                  skipped: skipped,
                  onSkipLine: onSkip,
                  batch: batch ?? (body) async => await body(),
                  onAccept: (mention, _) async =>
                      events?.add('link ${mention.surface}'),
                  onReject: (mention, _) async =>
                      events?.add('reject ${mention.surface}'),
                  onCreate: (_) async => events?.add('create'),
                  onIgnore: (_) async => events?.add('ignore'),
                  onAcceptLoan: (loan) async =>
                      events?.add('loan ${loan.line}'),
                  onRejectLoan: (loan) async => events?.add('reject loan'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('renders cards, warning, and one scrollable', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 640);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await mount(tester);
    expect(find.text('Wednesday 12 Nov · 3 lines to review'), findsOneWidget);
    expect(find.byKey(const ValueKey('enrich-card-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('enrich-card-2')), findsOneWidget);
    expect(find.byKey(const ValueKey('enrich-card-3')), findsOneWidget);
    expect(find.text('Link 2 + track loan'), findsOneWidget);
    expect(find.text('Track loan'), findsOneWidget);
    expect(find.byKey(const ValueKey('enrich-primary-3')), findsNothing);
    expect(find.text('choose…'), findsOneWidget);
    expect(find.byKey(const ValueKey('enrich-warning-1')), findsOneWidget);
    expect(find.text('Already out since 2026-01-01 (Sam)'), findsWidgets);
    expect(find.byType(Scrollable), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('primary links in order then tracks loan in one batch', (
    tester,
  ) async {
    final events = <String>[];
    var batches = 0;
    await mount(
      tester,
      events: events,
      batch: (body) async {
        batches++;
        await body();
      },
    );
    await tester.tap(find.byKey(const ValueKey('enrich-primary-1')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(events, ['link Camera', 'link Tripod', 'loan 1']);
    expect(batches, 1);
  });

  testWidgets('row menu links or rejects and hides the rejected row', (
    tester,
  ) async {
    final events = <String>[];
    await mount(tester, events: events);
    await tester.tap(find.byKey(const ValueKey('enrich-row-1-Camera')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Link to Camera'), findsOneWidget);
    expect(find.text('Other page…'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('enrich-menu-link')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byKey(const ValueKey('enrich-row-1-Tripod')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byKey(const ValueKey('enrich-menu-reject')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(events, ['link Camera', 'reject Tripod']);
    expect(find.byKey(const ValueKey('enrich-row-1-Tripod')), findsNothing);
  });

  testWidgets('not a loan rejects through one batch', (tester) async {
    final events = <String>[];
    var batches = 0;
    await mount(
      tester,
      events: events,
      batch: (body) async {
        batches++;
        await body();
      },
    );
    await tester.tap(find.byKey(const ValueKey('enrich-not-loan-1')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(events, ['reject loan']);
    expect(batches, 1);
  });

  testWidgets('skip hides card without recording a rejection', (tester) async {
    final events = <String>[];
    String? key;
    await mount(tester, events: events, onSkip: (value) => key = value);
    await tester.tap(find.byKey(const ValueKey('enrich-skip-1')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const ValueKey('enrich-card-1')), findsNothing);
    expect(events, isEmpty);
    expect(key, isNotNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await mount(tester, skipped: {key!});
    expect(find.byKey(const ValueKey('enrich-card-1')), findsNothing);
  });

  testWidgets('accept all confirms and runs bottom-up in one batch', (
    tester,
  ) async {
    final events = <String>[];
    var batches = 0;
    await mount(
      tester,
      events: events,
      batch: (body) async {
        batches++;
        await body();
      },
    );
    await tester.tap(find.byKey(const ValueKey('enrich-accept-all')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Link 2 mentions and track 2 loans?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(events, isEmpty);
    await tester.tap(find.byKey(const ValueKey('enrich-accept-all')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byKey(const ValueKey('enrich-accept-all-confirm')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(events, ['loan 2', 'link Camera', 'link Tripod', 'loan 1']);
    expect(batches, 1);
  });
}
