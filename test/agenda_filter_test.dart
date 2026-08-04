import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/app_mobile.dart';
import 'package:tylog_core/models.dart';

TaskRef _task({
  String id = 't1',
  String status = 'todo',
  String? due,
  String? scheduled,
}) => TaskRef(
  id: id,
  notePath: 'notes/a.typ',
  text: 'Task $id',
  status: status,
  priority: 'normal',
  due: due,
  scheduled: scheduled,
);

void main() {
  const today = '2026-07-15';

  test('includes a task due today', () {
    final task = _task(due: '2026-07-15');
    expect(isTaskInTodayAgenda(task, today), isTrue);
  });

  test('includes an overdue-scheduled task (scheduled before today)', () {
    final task = _task(scheduled: '2026-07-10');
    expect(isTaskInTodayAgenda(task, today), isTrue);
  });

  test('excludes tasks due or scheduled strictly in the future', () {
    expect(isTaskInTodayAgenda(_task(due: '2026-07-16'), today), isFalse);
    expect(isTaskInTodayAgenda(_task(scheduled: '2026-07-20'), today), isFalse);
  });

  test('excludes done and cancelled tasks even if due/scheduled today', () {
    expect(
      isTaskInTodayAgenda(_task(status: 'done', due: '2026-07-15'), today),
      isFalse,
    );
    expect(
      isTaskInTodayAgenda(
        _task(status: 'cancelled', scheduled: '2026-07-15'),
        today,
      ),
      isFalse,
    );
  });

  test('only unfinished tasks due before today are overdue', () {
    expect(isTaskOverdue(_task(due: '2026-07-14T23:00:00'), today), isTrue);
    expect(isTaskOverdue(_task(due: today), today), isFalse);
    expect(
      isTaskOverdue(_task(status: 'done', due: '2026-07-14'), today),
      isFalse,
    );
  });

  test('continue reading admits only articles', () {
    NoteRef note(String kind) => NoteRef(
      id: kind,
      path: 'notes/$kind.typ',
      title: kind,
      kind: kind,
      outgoingLinks: const [],
      tags: const [],
    );
    expect(continueReadingEligible(note('article')), isTrue);
    for (final kind in ['note', 'person', 'organization', 'project', 'daily']) {
      expect(continueReadingEligible(note(kind)), isFalse, reason: kind);
    }
  });
}
