import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tylog/widgets/loan_list.dart';
import 'package:tylog_core/tylog_core.dart';

void main() {
  const loan = TaskRef(
    id: 'one',
    notePath: 'day',
    text: 'Borrow camera',
    clocked: [ClockEntry(start: '2026-01-01T10:00:00Z')],
    properties: {
      'loan': true,
      'equipment': ['camera', 'tripod'],
      'purpose': 'Class',
    },
  );
  const returned = TaskRef(
    id: 'two',
    notePath: 'day',
    text: 'Returned',
    status: 'done',
    clocked: [
      ClockEntry(start: '2026-01-01T10:00:00Z', end: '2026-01-01T11:00:00Z'),
    ],
    properties: {'loan': true},
  );

  testWidgets('shows loan details and opens a row', (tester) async {
    TaskRef? opened;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LoanList(
            loans: const [loan, returned],
            titleOf: (id) => id.toUpperCase(),
            now: DateTime.utc(2026, 1, 1, 12, 10),
            onOpen: (task) => opened = task,
            summary: '2 loans · 3 h out · last returned 10 Nov',
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Borrow camera'), findsOneWidget);
    expect(
      find.text('2 loans · 3 h out · last returned 10 Nov'),
      findsOneWidget,
    );
    expect(
      find.text('CAMERA, TRIPOD · Class · out 2 h 10 min'),
      findsOneWidget,
    );
    expect(find.text('returned after 1 h 0 min'), findsOneWidget);
    expect(find.byIcon(Icons.outbox_outlined), findsOneWidget);
    expect(find.byIcon(Icons.check), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('loan-one')));
    await tester.pump(const Duration(milliseconds: 100));
    expect(opened, loan);
  });

  testWidgets('shows empty state', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LoanList(
            loans: const [],
            titleOf: (id) => id,
            now: DateTime.utc(2026),
            onOpen: (_) {},
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Nothing out'), findsOneWidget);
  });
}
