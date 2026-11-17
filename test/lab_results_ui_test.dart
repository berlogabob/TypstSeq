import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/lab_results.dart';
import 'package:tylog/widgets/task_chip_strip.dart';
import 'package:tylog_core/tylog_core.dart';

void main() {
  const task = TaskRef(
    id: 't',
    notePath: 'note.typ',
    text: 'loan',
    properties: {
      'loan': true,
      'equipment': ['a'],
    },
  );
  final results = labResults([
    '{"at":"2026-01-01T00:00:00Z","task":"t","tag":"a","step":"out","status":"refused","reason":"unavailable"}',
  ]);

  tearDown(() => labResultsNotifier.value = const {});

  testWidgets('loan chip follows lab results', (tester) async {
    labResultsNotifier.value = results;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TaskChipStrip(task: task, onCommand: (_) {}),
        ),
      ),
    );
    expect(find.text('OLT: refused'), findsOneWidget);
    labResultsNotifier.value = const {};
    await tester.pump();
    expect(find.textContaining('OLT:'), findsNothing);
  });

  test('refusals become incoming items until decided', () {
    final items = labRefusalIncoming([task], results, {}, '2026-01-01');
    expect(items, hasLength(1));
    expect(items.single.id, 'lab-refused-t');
    expect(items.single.path, 'olt:lab-refused/t');
    expect(items.single.title, 'OpenLabTwin refused: unavailable');
    expect(items.single.properties['note'], 'note.typ');
    expect(
      labRefusalIncoming([task], results, {'lab-refused-t'}, '2026-01-01'),
      isEmpty,
    );
  });
}
