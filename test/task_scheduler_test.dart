import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/models.dart';
import 'package:tylog/task_scheduler.dart';
import 'package:tylog/typst_rag_client.dart';

void main() {
  test('task reminders handle one-off and recurring tasks', () {
    final now = DateTime.utc(2026, 7, 4, 8);
    const oneOff = TaskRef(
      id: 'one',
      notePath: 'pages/a.typ',
      text: 'One',
      remind: '2026-07-04T09:00:00Z',
    );
    const recurring = TaskRef(
      id: 'repeat',
      notePath: 'pages/a.typ',
      text: 'Repeat',
      remind: '2026-07-01T09:00:00Z',
      recurrence: 'RRULE:FREQ=DAILY',
    );
    expect(nextTaskReminder(oneOff, now), DateTime.utc(2026, 7, 4, 9));
    expect(nextTaskReminder(recurring, now), DateTime.utc(2026, 7, 4, 9));
  });

  test('unknown variables get a deterministic source-mode fix', () {
    expect(
      deterministicTypstFix('unknown variable: текст', '#текст'),
      contains('#pkm.tag("текст")'),
    );
  });
}
