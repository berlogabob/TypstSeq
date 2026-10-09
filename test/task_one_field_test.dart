import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/widgets/task_fields.dart';
import 'package:tylog_core/scanner.dart';

void main() {
  const source = '''
#tylog.task(
  id: "t1",
  text: "pay",
  due: "2026-10-10",
  scheduled: "2026-10-09",
  status: "todo",
  priority: "low",
  recurrence: "RRULE:FREQ=DAILY",
)
''';
  const all = {
    'priority': 'low',
    'due': '2026-10-10',
    'scheduled': '2026-10-09',
    'recurrence': 'RRULE:FREQ=DAILY',
  };
  for (final field in ['repeat', 'due', 'scheduled']) {
    testWidgets('$field list popup clears only its field and compiles', (
      tester,
    ) async {
      String? picked;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  picked = await showDialog<String>(
                    context: context,
                    builder: (_) => Dialog(child: TaskFieldPopup(field: field)),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('none'), findsOneWidget);
      await tester.tap(find.text('none'));
      await tester.pumpAndSettle();
      expect(picked, 'none');
      final out = setOneTaskField(source, 't1', field, picked!);
      final key = field == 'repeat' ? 'recurrence' : field;
      expect(out, source.replaceFirst('$key: "${all[key]}"', '$key: none'));
      final dir = Directory('.dart_tool/list_clear_test')
        ..createSync(recursive: true);
      addTearDown(() => dir.deleteSync(recursive: true));
      final file = File('${dir.path}/out.typ')
        ..writeAsStringSync('#import "/typst/tylog/lib.typ" as tylog\n$out');
      final result = Process.runSync('typst', [
        'compile',
        '--root',
        Directory.current.path,
        file.path,
        '${file.path}.pdf',
      ]);
      expect(result.exitCode, 0, reason: '${result.stderr}\n$out');
    });
  }

  for (final (field, key, value) in [
    ('priority', 'priority', 'high'),
    ('due', 'due', '2026-11-01'),
    ('scheduled', 'scheduled', '2026-11-01'),
    ('repeat', 'recurrence', 'RRULE:FREQ=WEEKLY'),
  ]) {
    test('a $field chip edit keeps every other field', () {
      final out = setOneTaskField(source, 't1', field, value);
      for (final entry in all.entries) {
        expect(
          taskField(out, entry.key),
          entry.key == key ? value : entry.value,
        );
      }
    });
  }
}
