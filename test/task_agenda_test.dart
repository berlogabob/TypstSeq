import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/models.dart';
import 'package:tylog/widgets/task_agenda.dart';
import 'package:tylog/widgets/work_surface.dart';

TaskRef task(
  String id, {
  String? due,
  String? scheduled,
  String? project,
  String path = 'notes/a.typ',
  String status = 'todo',
  List<String> completed = const [],
}) => TaskRef(
  id: id,
  notePath: path,
  text: 'Task $id',
  due: due,
  scheduled: scheduled,
  project: project,
  status: status,
  completed: completed,
);

void main() {
  const today = '2026-10-05';
  final notes = {
    'notes/a.typ': const NoteRef(
      id: 'a',
      path: 'notes/a.typ',
      title: 'Alpha',
      kind: 'note',
      outgoingLinks: [],
      tags: [],
    ),
    'daily/today.typ': const NoteRef(
      id: 'd',
      path: 'daily/today.typ',
      title: 'Daily',
      kind: 'daily',
      date: today,
      outgoingLinks: [],
      tags: [],
    ),
  };

  test(
    'agenda precedence, date boundaries, note/project groups and recent done',
    () {
      final groups = TaskAgendaCache().resolve(
        [
          task('overdue', due: '2026-10-04T23:00:00', path: 'daily/today.typ'),
          task('due', due: today),
          task('daily', path: 'daily/today.typ'),
          task('scheduled', scheduled: '2026-10-01'),
          task('tomorrow', due: '2026-10-06'),
          task('edge', due: '2026-10-19'),
          task('later', due: '2026-10-20'),
          task('project', project: 'Work'),
          task('undated'),
          task('done', status: 'done', completed: ['2026-09-29T12:00:00']),
          task('old', status: 'done', completed: ['2026-09-28']),
          task('unknown', status: 'done'),
          task('future', status: 'done', completed: ['2026-10-06']),
          task('cancelled', status: 'cancelled', due: today),
        ],
        notes,
        today,
      );
      expect(groups.map((g) => g.key), [
        'overdue',
        'today',
        'upcoming:2026-10-06',
        'upcoming:2026-10-19',
        'later',
        'note:notes/a.typ',
        'project:Work',
        'done',
      ]);
      expect(groups[0].tasks.single.id, 'overdue');
      expect(
        groups[1].tasks.map((t) => t.id),
        containsAll(['due', 'daily', 'scheduled']),
      );
      expect(groups[5].title, 'Alpha');
      expect(groups.last.tasks.single.id, 'done');
      expect(groups.where((g) => g.collapsed).length, 3);
    },
  );

  test('cache reuses grouping and sorting until identity or day changes', () {
    final cache = TaskAgendaCache();
    final tasks = [task('a', due: today)];
    final first = cache.resolve(tasks, notes, today);
    expect(identical(first, cache.resolve(tasks, notes, today)), isTrue);
    expect(
      identical(first, cache.resolve(tasks.toList(), notes, today)),
      isFalse,
    );
    expect(cache.resolve(tasks, notes, '2026-10-06').single.key, 'overdue');
  });

  test(
    'filters combine status, exact project and case-insensitive task text',
    () {
      final groups = TaskAgendaCache().resolve(
        [
          task('OPEN', project: 'Work'),
          task('other', project: 'Home'),
          task('DONE', status: 'done', completed: [today], project: 'Work'),
        ],
        notes,
        today,
      );
      expect(
        filterTaskAgenda(
          groups,
          TaskAgendaFilter.open,
          'Work',
          ' open ',
        ).single.tasks.single.id,
        'OPEN',
      );
      expect(
        filterTaskAgenda(
          groups,
          TaskAgendaFilter.done,
          null,
          '',
        ).single.tasks.single.id,
        'DONE',
      );
      expect(
        filterTaskAgenda(groups, TaskAgendaFilter.all, 'Work', '').length,
        2,
      );
      expect(
        filterTaskAgenda(groups, TaskAgendaFilter.open, null, 'missing'),
        isEmpty,
      );
    },
  );

  testWidgets(
    'collapsed groups build no task rows; expansion preserves actions',
    (tester) async {
      final tasks = [task('hidden', project: 'Work')];
      String? opened;
      String? status;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LibraryView(
              index: VaultIndex(
                notesByPath: notes,
                backlinksByTarget: {},
                tasks: tasks,
              ),
              calendar: const [],
              dayMarks: (daily: <String>{}, refs: <String>{}),
              progressByPath: const {},
              onOpenPath: (p) => opened = p,
              onOpenDay: (_) {},
              onSetTaskStatus: (t, s) async {
                status = s;
              },
              onSetReadStatus: (_, _) async {},
              onSetRelevance: (_, _) async {},
              onCreateNote: (_) {},
              onCreateEntity: () {},
              onImportMarkdownArticles: () async {},
              onReadPath: (_) {},
              onDeleteArticle: (_) async {},
            ),
          ),
        ),
      );
      await tester.tap(find.text('Tasks'));
      await tester.pumpAndSettle();
      expect(find.text('Task hidden'), findsNothing);
      await tester.tap(find.text('Work · 1'));
      await tester.pumpAndSettle();
      expect(find.text('Task hidden'), findsOneWidget);
      await tester.tap(find.text('Task hidden'));
      expect(opened, 'notes/a.typ');
      await tester.tap(find.byType(Checkbox));
      expect(status, 'done');
      await tester.tap(find.text('Work · 1'));
      await tester.pumpAndSettle();
      expect(find.text('Task hidden'), findsNothing);
    },
  );
}
