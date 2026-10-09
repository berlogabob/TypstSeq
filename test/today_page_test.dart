import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/app_mobile.dart';
import 'package:tylog_core/models.dart';

NoteRef _article(String id) => NoteRef(
  id: id,
  path: 'articles/$id.typ',
  title: 'Article $id',
  kind: 'article',
  outgoingLinks: const [],
  tags: const [],
);

TaskRef _task(String id, {String? due}) => TaskRef(
  id: id,
  text: 'Task $id',
  notePath: 'notes/$id.typ',
  status: 'todo',
  due: due,
);

void main() {
  testWidgets('Today agenda shows indexing before tasks arrive', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TodayPage(
            indexing: true,
            tasks: const [],
            recent: const [],
            editor: const SizedBox(),
            onOpenPath: (_) {},
            onSetStatus: (_, _) async {},
          ),
        ),
      ),
    );
    expect(find.text('Indexing…'), findsOneWidget);
    expect(find.text('Agenda · 0'), findsNothing);
  });

  testWidgets('Agenda lists events and due tasks for the shown day', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TodayPage(
            shownDay: DateTime(2001, 1, 2),
            events: const [
              CalendarItem(
                date: '2001-01-02',
                start: '09:00',
                kind: CalendarItemKind.dateRef,
                title: 'Shown class',
                notePath: 'events/class.typ',
              ),
              CalendarItem(
                date: '2001-01-03',
                kind: CalendarItemKind.dateRef,
                title: 'Other class',
                notePath: 'events/other.typ',
              ),
            ],
            tasks: [
              _task('shown', due: '2001-01-02'),
              _task('other', due: '2001-01-03'),
            ],
            recent: const [],
            editor: const SizedBox(),
            onOpenPath: (_) {},
            onSetStatus: (_, _) async {},
          ),
        ),
      ),
    );
    expect(find.text('Agenda · 2'), findsOneWidget);
    expect(find.text('Shown class'), findsNothing);
    await tester.tap(find.text('Agenda · 2'));
    await tester.pumpAndSettle();
    expect(find.text('Shown class'), findsOneWidget);
    expect(find.text('Task shown'), findsOneWidget);
    expect(find.text('Other class'), findsNothing);
    expect(find.text('Task other'), findsNothing);
  });

  testWidgets('Empty shown day links to the earliest next feed event', (
    tester,
  ) async {
    var day = DateTime(2001, 1, 2);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => TodayPage(
              shownDay: day,
              onOpenDay: (next) => setState(() => day = next),
              events: const [
                CalendarItem(
                  date: '2001-01-04',
                  start: '2001-01-04T08:00',
                  kind: CalendarItemKind.dateRef,
                  title: 'Later class',
                  notePath: 'events/later.typ',
                ),
                CalendarItem(
                  date: '2001-01-03',
                  start: '08:00',
                  kind: CalendarItemKind.dateRef,
                  title: 'Lab',
                  notePath: 'events/lab.typ',
                ),
                CalendarItem(
                  date: '2001-01-03',
                  start: '2001-01-03T09:00',
                  kind: CalendarItemKind.dateRef,
                  title: 'Consultation',
                  notePath: 'events/consultation.typ',
                ),
                CalendarItem(
                  date: '2001-01-01',
                  start: '2001-01-01T08:00',
                  kind: CalendarItemKind.dateRef,
                  title: 'Past class',
                  notePath: 'events/past.typ',
                ),
              ],
              tasks: const [],
              recent: const [],
              editor: const SizedBox(),
              onOpenPath: (_) {},
              onSetStatus: (_, _) async {},
            ),
          ),
        ),
      ),
    );
    final next = find.text('No classes · Next: Wed 3 Jan 08:00 Lab');
    expect(next, findsOneWidget);
    expect(find.text('Lab'), findsNothing);
    await tester.tap(next);
    await tester.pumpAndSettle();
    expect(day, DateTime(2001, 1, 3));
    expect(find.text('Agenda · 2'), findsOneWidget);
    expect(find.text('Consultation'), findsNothing);
    await tester.tap(find.text('Agenda · 2'));
    await tester.pumpAndSettle();
    expect(find.text('Consultation'), findsOneWidget);
    expect(find.text('Lab'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Lab')).dy,
      lessThan(tester.getTopLeft(find.text('Consultation')).dy),
    );
  });

  testWidgets('Agenda and Overdue start collapsed and remember expansion', (
    tester,
  ) async {
    final bucket = PageStorageBucket();
    Widget page({bool show = true}) => MaterialApp(
      home: Scaffold(
        body: PageStorage(
          bucket: bucket,
          child: show
              ? TodayPage(
                  tasks: [
                    _task('due', due: '2000-01-01'),
                    _task('undated'),
                  ],
                  recent: const [],
                  editor: const SizedBox(),
                  onOpenPath: (_) {},
                  onSetStatus: (_, _) async {},
                )
              : const SizedBox(),
        ),
      ),
    );
    await tester.pumpWidget(page());
    expect(find.text('Agenda · 1'), findsOneWidget);
    expect(find.text('Tasks · 1'), findsNothing);
    expect(find.text('Task due'), findsNothing);
    expect(find.text('Task undated'), findsNothing);
    await tester.tap(find.text('Agenda · 1'));
    await tester.pumpAndSettle();
    expect(find.text('Task due'), findsNothing);
    await tester.tap(find.text('Overdue · 1'));
    await tester.pumpAndSettle();
    expect(find.text('Task due'), findsOneWidget);
    expect(find.text('Task undated'), findsNothing);
    await tester.pumpWidget(page(show: false));
    await tester.pumpWidget(page());
    await tester.pumpAndSettle();
    expect(find.text('Task due'), findsOneWidget);
    expect(find.text('Task undated'), findsNothing);
  });

  testWidgets('Agenda orders events, shows today tasks and links to all tasks', (
    tester,
  ) async {
    final now = DateTime.now();
    final today =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    var openedTasks = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TodayPage(
            events: [
              CalendarItem(
                date: today,
                start: '${today}T15:00',
                kind: CalendarItemKind.dateRef,
                title: 'Lab',
                notePath: 'events/lab.typ',
              ),
              CalendarItem(
                date: today,
                start: '${today}T09:00',
                kind: CalendarItemKind.dateRef,
                title: 'Class',
                notePath: 'events/class.typ',
              ),
              CalendarItem(
                date: '2000-01-01',
                kind: CalendarItemKind.dateRef,
                title: 'Old event',
                notePath: 'events/old.typ',
              ),
            ],
            tasks: [
              _task('today', due: today),
              TaskRef(
                id: 'scheduled',
                text: 'Scheduled task',
                notePath: 'notes/s.typ',
                scheduled: today,
              ),
              _task('overdue', due: '2000-01-01'),
              _task('future', due: '9999-01-01'),
              _task('undated'),
              TaskRef(
                id: 'done',
                text: 'Done task',
                notePath: 'notes/d.typ',
                due: today,
                status: 'done',
              ),
            ],
            recent: const [],
            editor: const SizedBox(),
            onOpenPath: (_) {},
            onSetStatus: (_, _) async {},
            onAllTasks: () => openedTasks = true,
          ),
        ),
      ),
    );
    expect(find.text('Agenda · 5'), findsOneWidget);
    expect(find.text('All tasks →'), findsNothing);
    await tester.tap(find.text('Agenda · 5'));
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.text('Class')).dy,
      lessThan(tester.getTopLeft(find.text('Lab')).dy),
    );
    expect(find.text('Task today'), findsOneWidget);
    expect(find.text('Scheduled task'), findsOneWidget);
    expect(find.text('Task overdue'), findsNothing);
    expect(find.text('Task future'), findsNothing);
    expect(find.text('Task undated'), findsNothing);
    expect(find.text('Done task'), findsNothing);
    expect(find.text('Old event'), findsNothing);
    await tester.ensureVisible(find.text('All tasks →'));
    await tester.tap(find.text('All tasks →'));
    expect(openedTasks, isTrue);
  });

  testWidgets('continue reading renders each entry as a card with progress', (
    tester,
  ) async {
    final opened = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TodayPage(
            tasks: const [],
            recent: [(_article('a'), 0.4), (_article('b'), 0.0)],
            editor: const SizedBox(),
            onOpenPath: (_) {},
            onSetStatus: (task, status) async {},
            onReadPath: opened.add,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(Card), findsNothing);
    await tester.tap(find.text('Continue reading'));
    await tester.pumpAndSettle();
    expect(find.byType(Card), findsNWidgets(2));
    expect(find.text('40%'), findsOneWidget);
    expect(find.text('0%'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(Card),
        matching: find.byType(LinearProgressIndicator),
      ),
      findsNWidgets(2),
    );

    await tester.tap(find.text('Article a'));
    expect(opened, ['articles/a.typ']);
  });

  testWidgets('with nothing due the editor gets the whole page', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TodayPage(
            tasks: const [],
            recent: const [],
            editor: Container(key: const Key('editor')),
            onOpenPath: (_) {},
            onSetStatus: (task, status) async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final editorSize = tester.getSize(find.byKey(const Key('editor')));
    final pageSize = tester.getSize(find.byType(TodayPage));
    expect(editorSize.height, greaterThanOrEqualTo(pageSize.height * 0.8));
    expect(find.text('Nothing actionable today'), findsNothing);
  });

  testWidgets('a populated agenda never takes more than half the page', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TodayPage(
            tasks: [
              for (var i = 0; i < 8; i++)
                _task('t$i', due: '2000-01-0${i + 1}'),
            ],
            recent: [for (var i = 0; i < 8; i++) (_article('a$i'), 0.1 * i)],
            editor: Container(key: const Key('editor')),
            onOpenPath: (_) {},
            onSetStatus: (task, status) async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final editorSize = tester.getSize(find.byKey(const Key('editor')));
    final pageSize = tester.getSize(find.byType(TodayPage));
    expect(editorSize.height, greaterThanOrEqualTo(pageSize.height * 0.5));
  });

  testWidgets(
    'agenda row tap opens the note; completing stays the checkbox\'s job',
    (tester) async {
      final opened = <String>[];
      var setStatusCalls = 0;
      // Fixed past date so the task is always in today's agenda regardless
      // of when this test runs.
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TodayPage(
              tasks: [_task('t1', due: '2000-01-01')],
              recent: const [],
              editor: const SizedBox(),
              onOpenPath: opened.add,
              onSetStatus: (task, status) async {
                setStatusCalls++;
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Task t1'), findsNothing);
      await tester.tap(find.text('Agenda · 1'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Overdue · 1'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Task t1'));
      expect(opened, ['notes/t1.typ']);
      expect(setStatusCalls, 0);
    },
  );
}
