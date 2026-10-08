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
