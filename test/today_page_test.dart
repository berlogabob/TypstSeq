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
  testWidgets('Agenda and Tasks start collapsed and remember expansion', (
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
    expect(find.text('Tasks · 1'), findsOneWidget);
    expect(find.text('Task due'), findsNothing);
    expect(find.text('Task undated'), findsNothing);
    await tester.tap(find.text('Agenda · 1'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tasks · 1'));
    await tester.pumpAndSettle();
    expect(find.text('Task due'), findsOneWidget);
    expect(find.text('Task undated'), findsOneWidget);
    await tester.pumpWidget(page(show: false));
    await tester.pumpWidget(page());
    await tester.pumpAndSettle();
    expect(find.text('Task due'), findsOneWidget);
    expect(find.text('Task undated'), findsOneWidget);
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
      await tester.tap(find.text('Task t1'));
      expect(opened, ['notes/t1.typ']);
      expect(setStatusCalls, 0);
    },
  );
}
