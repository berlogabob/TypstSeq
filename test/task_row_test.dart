import 'package:tylog/vault_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/knowledge_screen.dart';
import 'package:tylog/models.dart';
import 'package:tylog/saved_searches.dart';
import 'package:tylog/vault.dart';
import 'package:tylog/widgets/calendar_tab.dart';
import 'package:tylog/widgets/journal_feed.dart';
import 'package:tylog/widgets/task_row.dart';
import 'package:tylog/widgets/work_surface.dart';
import 'package:tylog_core/search_index.dart';

void main() {
  testWidgets(
    'TaskRow glyphs, toggle, status menu, source and shared field chips',
    (tester) async {
      tester.view.physicalSize = const Size(480, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final changes = <String>[];
      String? opened;
      for (final (status, glyph) in const [
        ('todo', '☐'),
        ('doing', '◐'),
        ('done', '☑'),
        ('cancelled', '☒'),
      ]) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: TaskRow(
                task: TaskRef(
                  id: 't',
                  notePath: 'notes/t.typ',
                  text: 'Call bank',
                  status: status,
                  priority: 'high',
                  due: '2026-10-08',
                  scheduled: '2026-10-09',
                  recurrence: 'RRULE:FREQ=DAILY',
                  clocked: const [
                    ClockEntry(
                      start: '2026-10-08T09:00:00Z',
                      end: '2026-10-08T09:05:00Z',
                    ),
                  ],
                ),
                onOpenPath: (path) => opened = path,
                onSetStatus: (_, next) async => changes.add(next),
                onSetField: (_, field, value) async =>
                    changes.add('$field:$value'),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text(glyph), findsOneWidget);
        await tester.tap(find.byTooltip('Task status'));
        expect(changes.last, status == 'done' ? 'todo' : 'done');
        await tester.longPress(find.byTooltip('Task status'));
        await tester.pumpAndSettle();
        for (final state in ['todo', 'doing', 'done', 'cancelled']) {
          expect(find.text(state), findsOneWidget);
        }
        await tester.tap(find.text('cancelled'));
        await tester.pumpAndSettle();
        expect(changes.last, 'cancelled');
        for (final field in [
          'priority',
          'due',
          'scheduled',
          'repeat',
          'time',
        ]) {
          expect(find.byKey(Key('task-chip-t-$field')), findsOneWidget);
        }
        expect(find.byTooltip('Start timer'), findsNothing);
        expect(find.byTooltip('Stop timer'), findsNothing);
        expect(find.text('05:00'), findsOneWidget);
        await tester.tap(find.text('Call bank'));
        expect(opened, 'notes/t.typ');
        expect(tester.takeException(), isNull);
      }
      tester.view.physicalSize = const Size(320, 800);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const Key('task-chip-t-priority')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('urgent'));
      await tester.pumpAndSettle();
      expect(changes.last, 'priority:urgent');
      for (final field in ['due', 'scheduled']) {
        await tester.tap(find.byKey(Key('task-chip-t-$field')));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('task-date-input')),
          'tomorrow',
        );
        await tester.pumpAndSettle();
        final tomorrow = DateTime.now()
            .add(const Duration(days: 1))
            .toIso8601String()
            .split('T')
            .first;
        await tester.tap(find.text(tomorrow));
        await tester.pumpAndSettle();
        expect(changes.last, '$field:$tomorrow');
      }
      await tester.tap(find.byKey(const Key('task-chip-t-repeat')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('weekly'));
      await tester.pumpAndSettle();
      expect(changes.last, 'repeat:RRULE:FREQ=WEEKLY');
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final field in ['priority', 'due', 'scheduled', 'repeat']) {
    testWidgets(
      '$field popup fits its rows above bottom navigation and keyboard',
      (tester) async {
        tester.view.physicalSize = const Size(405, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetViewInsets);
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData.dark(),
            home: Scaffold(
              bottomNavigationBar: const SizedBox(
                key: Key('bottom-bar'),
                height: 80,
              ),
              body: Align(
                alignment: Alignment.bottomCenter,
                child: SizedBox(
                  height: 140,
                  child: TaskRow(
                    task: TaskRef(
                      id: 't',
                      notePath: 'notes/t.typ',
                      text: 'Bottom task',
                    ),
                    onOpenPath: (_) {},
                    onSetField: (_, _, _) async {},
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.byKey(Key('task-chip-t-$field')));
        await tester.pumpAndSettle();
        final popup = find
            .ancestor(
              of: find.text(
                field == 'priority'
                    ? 'urgent'
                    : field == 'repeat'
                    ? 'daily'
                    : 'none',
              ),
              matching: find.byType(Material),
            )
            .first;
        final rect = tester.getRect(popup);
        expect(
          rect.bottom,
          lessThanOrEqualTo(
            tester.getTopLeft(find.byKey(const Key('bottom-bar'))).dy,
          ),
        );
        expect(
          rect.bottom,
          lessThanOrEqualTo(
            tester.getTopLeft(find.byKey(Key('task-chip-t-$field'))).dy,
          ),
        );
        expect(
          rect.height,
          closeTo(
            field == 'priority'
                ? 192
                : field == 'repeat'
                ? 240
                : 104,
            1,
          ),
        );
        if (field == 'due' || field == 'scheduled') {
          tester.view.viewInsets = const FakeViewPadding(bottom: 350);
          await tester.pumpAndSettle();
          await tester.enterText(
            find.byKey(const Key('task-date-input')),
            'tomorrow',
          );
          await tester.pumpAndSettle();
          expect(tester.getRect(popup).bottom, lessThanOrEqualTo(550));
          expect(
            find.text(
              DateTime.now()
                  .add(const Duration(days: 1))
                  .toIso8601String()
                  .split('T')
                  .first,
            ),
            findsOneWidget,
          );
          await tester.enterText(
            find.byKey(const Key('task-date-input')),
            'tomorrow 13:30',
          );
          await tester.pumpAndSettle();
          expect(find.text('13:30'), findsOneWidget);
          expect(
            tester.getRect(popup).bottom,
            closeTo(
              tester
                  .getRect(
                    find
                        .ancestor(
                          of: find.text('none'),
                          matching: find.byType(ListTile),
                        )
                        .first,
                  )
                  .bottom,
              1,
            ),
          );
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  for (final surface in [
    'Today',
    'Overdue',
    'Tasks',
    'Journal',
    'Calendar',
    'Search',
    'Saved query',
  ]) {
    testWidgets('$surface renders TaskRow and forwards status and fields', (
      tester,
    ) async {
      final day = DateTime.now().toIso8601String().split('T').first;
      final task = TaskRef(
        id: 't',
        notePath:
            'daily/${day.substring(0, 4)}/${day.substring(5, 7)}/$day.typ',
        text: 'Surface task',
        due: surface == 'Overdue' ? '2000-01-01' : day,
      );
      final index = VaultIndex(
        notesByPath: {
          task.notePath: NoteRef(
            id: 'daily',
            path: task.notePath,
            title: day,
            kind: 'daily',
            date: day,
            outgoingLinks: const [],
          ),
        },
        backlinksByTarget: {},
        tasks: [task],
      );
      String? changed;
      Future<void> status(TaskRef t, String value) async {
        expect(t.id, 't');
        changed = value;
      }

      Future<void> field(TaskRef t, String name, String value) async {
        expect(t.id, 't');
        changed = '$name:$value';
      }

      Widget content;
      switch (surface) {
        case 'Today':
        case 'Overdue':
          content = TodayPage(
            tasks: [task],
            recent: const [],
            editor: const SizedBox(),
            notes: index.notesByPath,
            onOpenPath: (_) {},
            onSetStatus: status,
            onSetField: field,
          );
        case 'Tasks':
          content = LibraryView(
            initialTab: 3,
            index: index,
            calendar: index.calendar,
            dayMarks: index.calendarDayMarks,
            progressByPath: const {},
            onOpenPath: (_) {},
            onOpenDay: (_) {},
            onSetTaskStatus: status,
            onSetTaskField: field,
            onSetReadStatus: (_, _) async {},
            onSetRelevance: (_, _) async {},
            onCreateNote: (_) {},
            onCreateEntity: () {},
            onImportMarkdownArticles: () async {},
            onReadPath: (_) {},
            onDeleteArticle: (_) async {},
          );
        case 'Calendar':
          content = CalendarTab(
            index: index,
            calendar: index.calendar,
            dayMarks: index.calendarDayMarks,
            onOpenPath: (_) {},
            onOpenDay: (_) {},
            onSetStatus: status,
            onSetField: field,
          );
        case 'Journal':
          final vault = Vault.withStorage(
            _JournalStorage('#tylog.task(id: "t", text: "Surface task")'),
          );
          content = JournalFeed(
            vault: vault,
            index: index,
            onOpenPath: (_) {},
            onSetStatus: status,
            onSetField: field,
          );
        default:
          content = KnowledgeScreen(
            index: index,
            problems: const [],
            onOpenNote: (_) {},
            onSetTaskStatus: status,
            onSetTaskField: field,
            savedSearches: surface == 'Saved query'
                ? const [SavedSearch(name: 'My tasks', query: 'Surface')]
                : const [],
            search: (_, _, _) async => [
              PkmsSearchResult(
                id: 't',
                path: task.notePath,
                title: task.text,
                kind: 'task',
                tags: const [],
                score: 1,
              ),
            ],
          );
      }
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: content)));
      if (surface == 'Journal') {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
      }
      await tester.pumpAndSettle();
      if (surface == 'Today' || surface == 'Overdue') {
        await tester.tap(find.text('Agenda · 1'));
        await tester.pumpAndSettle();
        if (surface == 'Overdue') {
          await tester.tap(find.text('Overdue · 1'));
          await tester.pumpAndSettle();
        }
      }
      if (surface == 'Saved query') {
        await tester.tap(find.text('My tasks'));
        await tester.pumpAndSettle();
      }
      if (surface == 'Calendar') {
        await tester.scrollUntilVisible(
          find.byType(TaskRow),
          150,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
      }
      expect(find.byType(TaskRow), findsOneWidget);
      await tester.ensureVisible(find.byTooltip('Task status'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Task status'));
      expect(changed, 'done');
      await tester.longPress(find.byTooltip('Task status'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('doing'));
      await tester.pumpAndSettle();
      expect(changed, 'doing');
      await tester.ensureVisible(find.byKey(const Key('task-chip-t-priority')));
      await tester.tap(find.byKey(const Key('task-chip-t-priority')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('urgent'));
      await tester.pumpAndSettle();
      expect(changed, 'priority:urgent');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}

class _JournalStorage implements VaultStorage {
  _JournalStorage(this.source);
  final String source;
  @override
  Future<String> readText(String path) async => source;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
