import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tylog/rich_editor.dart';
import 'package:tylog/widgets/task_fields.dart';
import 'package:tylog/widgets/task_row.dart';
import 'package:tylog_core/tylog_core.dart';
import 'package:tylog_core/src/values.dart' show typstString;

const _texts = [
  'Студент 20239876 взял QUEST 3 [2] домой до пятницы',
  'call (x) back',
  'ticket #3 done',
  'buy *milk* and _eggs_',
  'all: [a] (b) #c *d* _e_ \\ "q" @x',
];

String _source(String text) =>
    '#tylog.task(\n  id: "t1",\n  text: ${typstString(text)},\n'
    '  status: "doing",\n  due: "2026-11-13",\n'
    '  properties: (loan: true, clocked: (("2026-11-12T21:51:31Z", none),)),\n)';

void main() {
  for (final text in _texts) {
    final source = '${_source(text)}\n\nafter\n';

    test('round trip is byte-identical: $text', () {
      final doc = TyLogDocument.parse(source);
      expect(doc.blocks.first.style, TyLogBlockStyle.taskLine);
      expect(doc.blocks.first.visibleText.substring(2), text);
      expect(doc.toSource(), source);
      expect(taskField(doc.blocks.first.originalSource, 'text'), text);
    });

    testWidgets('read view shows one paragraph with exact text: $text', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: SizedBox(
                width: 360,
                child: TyLogReadView(
                  source: source,
                  taskBuilder: (s) => TaskRow(
                    task: taskFromSource(s, notePath: 'a.typ'),
                    onOpenPath: (_) {},
                    compact: true,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(text), findsOneWidget);
      // One task row (one title Text), chips below it, no stray gap between.
      final title = tester.getRect(find.text(text));
      final due = tester.getRect(find.text('due 13 Nov'));
      expect(due.top - title.bottom, lessThan(24));
    });
  }
}
