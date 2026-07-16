import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/models.dart';
import 'package:tylog/task_scheduler.dart';
import 'package:tylog/controlled_editor.dart';

void main() {
  test('task reminders handle one-off and recurring tasks', () {
    final now = DateTime.utc(2026, 7, 4, 8);
    const oneOff = TaskRef(
      id: 'one',
      notePath: 'notes/a.typ',
      text: 'One',
      remind: '2026-07-04T09:00:00Z',
    );
    const recurring = TaskRef(
      id: 'repeat',
      notePath: 'notes/a.typ',
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
      contains('#tylog.tag("текст")'),
    );
  });

  test(
    'a malformed recurrence disables the reminder but is not fully silent',
    () {
      final now = DateTime.utc(2026, 7, 4, 8);
      const task = TaskRef(
        id: 'bad-rrule',
        notePath: 'notes/a.typ',
        text: 'Broken',
        remind: '2026-07-01T09:00:00Z',
        recurrence: 'not a valid rrule',
      );

      final messages = <String>[];
      final previous = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null) messages.add(message);
      };
      addTearDown(() => debugPrint = previous);

      expect(nextTaskReminder(task, now), isNull);
      expect(
        messages,
        anyElement(
          allOf(contains('Invalid recurrence'), contains('bad-rrule')),
        ),
      );
    },
  );

  group('validateTaskRecurrences', () {
    test('flags a task with an unparseable recurrence', () {
      const task = TaskRef(
        id: 't1',
        notePath: 'notes/a.typ',
        text: 'Broken',
        recurrence: 'not a valid rrule',
      );

      final problems = validateTaskRecurrences([task]);

      expect(problems, hasLength(1));
      expect(problems.single.code, 'invalid-recurrence');
      expect(problems.single.severity, PkmsSeverity.warning);
      expect(problems.single.subject, 'notes/a.typ');
      expect(problems.single.message, contains('t1'));
    });

    test('does not flag a valid recurrence or an absent one', () {
      const withValid = TaskRef(
        id: 't2',
        notePath: 'notes/a.typ',
        text: 'Fine',
        recurrence: 'RRULE:FREQ=DAILY',
      );
      const withoutRecurrence = TaskRef(
        id: 't3',
        notePath: 'notes/a.typ',
        text: 'No recurrence',
      );

      expect(validateTaskRecurrences([withValid, withoutRecurrence]), isEmpty);
    });
  });

  group('stableTaskNotificationId', () {
    test('is stable across calls for the same id', () {
      expect(
        stableTaskNotificationId('task-1'),
        stableTaskNotificationId('task-1'),
      );
    });

    test('differs for different ids and stays a positive 31-bit int', () {
      final a = stableTaskNotificationId('task-1');
      final b = stableTaskNotificationId('task-2');
      expect(a, isNot(b));
      expect(a, greaterThanOrEqualTo(0));
      expect(a, lessThanOrEqualTo(0x7fffffff));
      expect(b, greaterThanOrEqualTo(0));
      expect(b, lessThanOrEqualTo(0x7fffffff));
    });
  });
}
