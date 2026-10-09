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
    'All includes cancelled and older or untimestamped done; Open and Done stay unchanged',
    () {
      final groups = TaskAgendaCache().resolve(
        [
          task('todo'),
          task('doing', status: 'doing'),
          task('recent', status: 'done', completed: [today]),
          task('old', status: 'done', completed: ['2000-01-01']),
          task('untimestamped', status: 'done'),
          task('cancelled', status: 'cancelled'),
        ],
        notes,
        today,
      );
      List<String> ids(TaskAgendaFilter filter) => filterTaskAgenda(
        groups,
        filter,
        null,
        '',
      ).expand((g) => g.tasks).map((t) => t.id).toList();
      expect(
        ids(TaskAgendaFilter.all),
        unorderedEquals([
          'todo',
          'doing',
          'recent',
          'old',
          'untimestamped',
          'cancelled',
        ]),
      );
      expect(ids(TaskAgendaFilter.open), unorderedEquals(['todo', 'doing']));
      expect(ids(TaskAgendaFilter.done), ['recent']);
    },
  );

  test('agenda cache follows in-place index task and note updates', () {
    final tasks = [task('a', due: today)];
    final noteMap = Map<String, NoteRef>.of(notes);
    final cache = TaskAgendaCache();
    final first = cache.resolve(tasks, noteMap, today);
    tasks[0] = TaskRef(
      id: 'a',
      notePath: 'notes/a.typ',
      text: 'Task a',
      due: today,
      clocked: const [ClockEntry(start: '2026-10-05T09:00:00Z')],
    );
    final next = cache.resolve(tasks, noteMap, today);
    expect(next.single.tasks.single.runningClock, isNotNull);
    expect(identical(next, first), isFalse);
    expect(cache.resolve(tasks, noteMap, today), same(next));
    noteMap.clear();
    expect(identical(cache.resolve(tasks, noteMap, today), next), isFalse);
  });

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
        'older-done',
        'cancelled',
      ]);
      expect(groups[0].tasks.single.id, 'overdue');
      expect(
        groups[1].tasks.map((t) => t.id),
        containsAll(['due', 'daily', 'scheduled']),
      );
      expect(groups[5].title, 'Alpha');
      expect(groups.firstWhere((g) => g.key == 'done').tasks.single.id, 'done');
      expect(
        filterTaskAgenda(
          groups,
          TaskAgendaFilter.all,
          null,
          '',
        ).expand((g) => g.tasks).length,
        14,
      );
      expect(
        filterTaskAgenda(
          groups,
          TaskAgendaFilter.done,
          null,
          '',
        ).single.tasks.single.id,
        'done',
      );
      expect(groups.where((g) => g.collapsed).length, 5);
    },
  );

  test(
    'journal months follow count-ranked no-date groups, newest day first',
    () {
      final journalNotes = {
        ...notes,
        'daily/2026/10/2026-10-01.typ': const NoteRef(
          id: 'fallback',
          path: 'daily/2026/10/2026-10-01.typ',
          title: 'Fallback',
          kind: 'note',
          outgoingLinks: [],
        ),
        'journal.typ': const NoteRef(
          id: 'journal',
          path: 'journal.typ',
          title: 'Journal',
          kind: 'daily',
          date: '2026-10-03',
          outgoingLinks: [],
        ),
      };
      final groups = TaskAgendaCache().resolve(
        [
          task('a'),
          task('b'),
          task('work', project: 'Work'),
          task('home', project: 'Home'),
          task('older', path: 'daily/2026/09/2026-09-30.typ'),
          task('early', path: 'daily/2026/10/2026-10-01.typ'),
          task('newer', path: 'journal.typ', project: 'Work'),
          task('dated', path: 'journal.typ', due: '2026-10-06'),
        ],
        journalNotes,
        today,
      );
      expect(groups.map((g) => g.key), [
        'upcoming:2026-10-06',
        'note:notes/a.typ',
        'project:Home',
        'project:Work',
        'journal:2026-10',
        'journal:2026-09',
      ]);
      expect(groups[4].title, 'October 2026');
      expect(groups[4].tasks.map((t) => t.id), ['newer', 'early']);
      expect(groups[4].collapsed, isTrue);
      expect(groups[5].collapsed, isTrue);
      expect(
        filterTaskAgenda(
          groups,
          TaskAgendaFilter.open,
          'Work',
          '',
        ).last.tasks.single.id,
        'newer',
      );
    },
  );

  test('cache reuses grouping and sorting until contents or day changes', () {
    final cache = TaskAgendaCache();
    final tasks = [task('a', due: today)];
    final first = cache.resolve(tasks, notes, today);
    expect(identical(first, cache.resolve(tasks, notes, today)), isTrue);
    expect(
      identical(first, cache.resolve(tasks.toList(), notes, today)),
      isTrue,
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
    'Library can open Tasks directly; collapsed groups preserve actions',
    (tester) async {
      final tasks = [
        task('hidden', project: 'Work'),
        task('journal', path: 'daily/2020/10/2020-10-03.typ'),
      ];
      String? opened;
      String? status;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LibraryView(
              initialTab: 3,
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
      await tester.pumpAndSettle();
      expect(find.text('Task hidden'), findsNothing);
      expect(find.text('Task journal'), findsNothing);
      expect(find.byType(TextField), findsNothing);
      await tester.tap(find.byTooltip('Search tasks'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'hidden');
      await tester.tap(find.byTooltip('Search tasks'));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsOneWidget);
      await tester.enterText(find.byType(TextField), '');
      await tester.tap(find.byTooltip('Search tasks'));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNothing);
      expect(find.text('From journal'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('From journal')).dy,
        greaterThan(tester.getTopLeft(find.text('No date')).dy),
      );
      await tester.tap(find.text('October 2020 · 1'));
      await tester.pumpAndSettle();
      expect(find.text('Task journal'), findsOneWidget);
      expect(find.text('Oct 3'), findsOneWidget);
      await tester.tap(find.text('October 2020 · 1'));
      await tester.pumpAndSettle();
      expect(find.text('Task journal'), findsNothing);
      await tester.tap(find.text('Work · 1'));
      await tester.pumpAndSettle();
      expect(find.text('Task hidden'), findsOneWidget);
      await tester.tap(find.text('Task hidden'));
      expect(opened, 'notes/a.typ');
      await tester.tap(find.byTooltip('Task status'));
      expect(status, 'done');
      await tester.tap(find.text('Work · 1'));
      await tester.pumpAndSettle();
      expect(find.text('Task hidden'), findsNothing);
    },
  );
}
