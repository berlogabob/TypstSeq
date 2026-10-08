import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/rich_editor.dart';
import 'package:tylog/task_scheduler.dart' show validateTaskRecurrences;
import 'package:tylog/widgets/date_format.dart';
import 'package:tylog_core/tylog_core.dart';

void main() {
  var serial = 0;
  TyLogEditingController editor([String source = '']) => TyLogEditingController(
    source: source,
    onSourceChanged: (_) {},
    onError: (e) => fail('$e'),
    onProtectedTap: (_) {},
    nextTaskId: (_) async => 'new-${serial++}',
  );
  void type(TyLogEditingController c, String text) {
    c.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  void check(TyLogEditingController c) {
    final source = c.document.toSource();
    expect(
      validateTaskRecurrences([
        for (final call in locateTypstCalls(
          source,
          names: const {'tylog.task'},
        ))
          TaskRef(
            id: taskField(call.source, 'id')!,
            notePath: 'task.typ',
            text: taskField(call.source, 'text')!,
            recurrence: taskField(call.source, 'recurrence'),
          ),
      ]),
      isEmpty,
    );
    expect(
      TyLogDocument.parse(source).visibleText.trimRight(),
      c.text.trimRight(),
    );
    final dir = Directory('.dart_tool/task_typing_test')
      ..createSync(recursive: true);
    final file = File('${dir.path}/task.typ')
      ..writeAsStringSync('#import "/typst/tylog/lib.typ" as tylog\n$source');
    final compiled = Process.runSync('typst', [
      'compile',
      '--root',
      Directory.current.path,
      file.path,
      '${file.path}.pdf',
    ]);
    expect(compiled.exitCode, 0, reason: '${compiled.stderr}\n$source');
  }

  tearDownAll(
    () => Directory('.dart_tool/task_typing_test').deleteSync(recursive: true),
  );

  for (final prefix in ['TODO ', '[] ', '[ ] ']) {
    test(
      '$prefix converts a paragraph line and survives late IME text',
      () async {
        final c = editor('before\nafter');
        addTearDown(c.dispose);
        type(c, 'before\n${prefix}call bank\nafter');
        c.selection = TextSelection.collapsed(
          offset: 'before\n${prefix}call bank'.length,
        );
        await Future<void>.delayed(Duration.zero);
        expect(c.text, 'before\n\n☐ call bank\n\nafter');
        check(c);
        type(c, 'before\n${prefix}call bank!\nafter');
        expect(c.text, 'before\n\n☐ call bank!\n\nafter');
        check(c);
      },
    );
  }
  test('Enter continues tasks and empty Enter exits', () async {
    final c = editor('#tylog.task(id: "t", text: "One")');
    addTearDown(c.dispose);
    type(c, '${c.text}\n');
    await Future<void>.delayed(Duration.zero);
    expect(c.text, '☐ One\n\n☐ ');
    check(c);
    type(c, '${c.text}\n');
    expect(c.text, '☐ One\n\n');
    check(c);
  });
  test('demote then undo restores full task metadata in one step', () {
    const source =
        '#tylog.task(id: "t", text: "One", priority: "high", due: "2026-10-09", recurrence: "RRULE:FREQ=WEEKLY", properties: (custom: "keep"))';
    final c = editor(source);
    addTearDown(c.dispose);
    c.value = const TextEditingValue(
      text: '☐One',
      selection: TextSelection.collapsed(offset: 1),
    );
    expect(c.text, 'One');
    c.undo();
    expect(c.document.toSource(), source);
    check(c);
  });
  for (final command in [
    'todo',
    'task',
    'doing',
    'done',
    'cancel',
    'a',
    'b',
    'c',
    'urgent',
    'due',
    'scheduled',
    'deadline',
    'repeat',
  ]) {
    testWidgets('/$command applies through the existing popup', (tester) async {
      final c = editor(
        command == 'todo' || command == 'task'
            ? 'Call bank'
            : '#tylog.task(id: "t", text: "Call bank")',
      );
      addTearDown(c.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TyLogRichEditor(controller: c, onInsert: () async {}),
          ),
        ),
      );
      final field = find.byKey(const Key('rich-journal-editor'));
      await tester.tap(field);
      type(c, '${c.text} /$command');
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      if (['due', 'scheduled', 'deadline'].contains(command)) {
        expect(find.byKey(const Key('task-date-input')), findsOneWidget);
        await tester.enterText(
          find.byKey(const Key('task-date-input')),
          'tomorrow',
        );
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();
        expect(
          c.document.toSource(),
          contains(
            '${command == 'due' ? 'due' : 'scheduled'}: "${isoDay(DateTime.now().add(const Duration(days: 1)))}"',
          ),
        );
      } else if (command == 'repeat') {
        await tester.tap(find.text('weekly'));
        await tester.pump();
        expect(
          c.document.toSource(),
          contains('recurrence: "RRULE:FREQ=WEEKLY"'),
        );
      } else if (['a', 'b', 'c', 'urgent'].contains(command)) {
        final priority = {
          'a': 'high',
          'b': 'normal',
          'c': 'low',
          'urgent': 'urgent',
        }[command];
        expect(c.document.toSource(), contains('priority: "$priority"'));
      } else {
        final status =
            {'task': 'todo', 'cancel': 'cancelled'}[command] ?? command;
        expect(taskField(c.document.toSource(), 'status') ?? 'todo', status);
      }
      expect(c.text, '${command == 'done' ? '☑' : '☐'} Call bank');
      check(c);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
  for (final words in ['tomorrow', 'завтра']) {
    testWidgets('date popup parses $words live', (tester) async {
      final c = editor('#tylog.task(id: "t", text: "Call")');
      addTearDown(c.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TyLogRichEditor(controller: c, onInsert: () async {}),
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('rich-journal-editor')));
      type(c, '${c.text} /due');
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      await tester.enterText(find.byKey(const Key('task-date-input')), words);
      await tester.pump();
      expect(
        find.text(isoDay(DateTime.now().add(const Duration(days: 1)))),
        findsOneWidget,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      check(c);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
  for (final repeat in ['daily', 'monthly', 'weekdays']) {
    testWidgets('/repeat selects $repeat', (tester) async {
      final c = editor('#tylog.task(id: "t", text: "Call")');
      addTearDown(c.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TyLogRichEditor(controller: c, onInsert: () async {}),
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('rich-journal-editor')));
      type(c, '${c.text} /repeat');
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      await tester.tap(find.text(repeat));
      await tester.pump();
      expect(
        c.document.toSource(),
        contains(
          'recurrence: "${repeat == 'weekdays' ? 'RRULE:FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR' : 'RRULE:FREQ=${repeat.toUpperCase()}'}"',
        ),
      );
      check(c);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
  testWidgets('Ctrl and Cmd Enter cycle task status', (tester) async {
    final c = editor('#tylog.task(id: "t", text: "Call")');
    addTearDown(c.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TyLogRichEditor(controller: c, onInsert: () async {}),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('rich-journal-editor')));
    for (final (modifier, status) in [
      (LogicalKeyboardKey.controlLeft, 'doing'),
      (LogicalKeyboardKey.metaLeft, 'done'),
      (LogicalKeyboardKey.controlLeft, 'todo'),
    ]) {
      await tester.sendKeyDownEvent(modifier);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(modifier);
      await tester.pump();
      expect(taskField(c.document.toSource(), 'status'), status);
      check(c);
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('long press checkbox opens four statuses on the line', (
    tester,
  ) async {
    final c = editor('#tylog.task(id: "t", text: "Call")');
    addTearDown(c.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TyLogRichEditor(controller: c, onInsert: () async {}),
        ),
      ),
    );
    final editable = tester
        .state<EditableTextState>(find.byType(EditableText))
        .renderEditable;
    final rect = editable.getLocalRectForCaret(const TextPosition(offset: 0));
    await tester.longPressAt(
      editable.localToGlobal(rect.center + const Offset(3, 0)),
    );
    await tester.pumpAndSettle();
    for (final status in ['todo', 'doing', 'done', 'cancelled']) {
      expect(find.text(status), findsOneWidget);
    }
    await tester.tap(find.text('doing'));
    await tester.pump();
    expect(taskField(c.document.toSource(), 'status'), 'doing');
    check(c);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  test(
    'conversion waits for composition and keeps edits during ID allocation',
    () async {
      final id = Completer<String>();
      final c = TyLogEditingController(
        source: '',
        onSourceChanged: (_) {},
        onError: (e) => fail('$e'),
        onProtectedTap: (_) {},
        nextTaskId: (_) => id.future,
      );
      addTearDown(c.dispose);
      c.value = const TextEditingValue(
        text: 'TODO Call',
        selection: TextSelection.collapsed(offset: 9),
        composing: TextRange(start: 5, end: 9),
      );
      expect(c.document.blocks.single.style, TyLogBlockStyle.paragraph);
      c.value = c.value.copyWith(composing: TextRange.empty);
      type(c, 'TODO Call bank');
      id.complete('allocated');
      await Future<void>.delayed(Duration.zero);
      expect(c.text, '☐ Call bank');
      check(c);
    },
  );
  testWidgets('date popup calendar fallback writes chosen date', (
    tester,
  ) async {
    final c = editor('#tylog.task(id: "t", text: "Call")');
    addTearDown(c.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TyLogRichEditor(controller: c, onInsert: () async {}),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('rich-journal-editor')));
    type(c, '${c.text} /due');
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    await tester.tap(find.byTooltip('Calendar'));
    await tester.pumpAndSettle();
    expect(find.byType(CalendarDatePicker), findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(taskField(c.document.toSource(), 'due'), isoDay(DateTime.now()));
    check(c);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets(
    'Android newline chooses slash command instead of inserting a task',
    (tester) async {
      final c = editor('#tylog.task(id: "t", text: "Call")');
      addTearDown(c.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TyLogRichEditor(controller: c, onInsert: () async {}),
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('rich-journal-editor')));
      type(c, '${c.text} /doing');
      await tester.pump();
      type(c, '${c.text}\n');
      await tester.pump();
      expect(c.text, '☐ Call');
      expect(taskField(c.document.toSource(), 'status'), 'doing');
      check(c);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  test('Doing starts and stops clocks and demotes a sibling Doing', () async {
    final c = editor(
      '#tylog.task(id: "a", text: "A")\n\n#tylog.task(id: "b", text: "B")',
    );
    addTearDown(c.dispose);
    await c.setTaskStatus(c.document.blocks.first.id, 'doing');
    expect(
      taskField(c.document.toSource().split('\n\n').first, 'status'),
      'doing',
    );
    expect(taskClocked(c.document.toSource(), 'a').single.end, isNull);
    await c.setTaskStatus(c.document.blocks.last.id, 'doing');
    expect(
      taskField(c.document.toSource().split('\n\n').first, 'status'),
      'todo',
    );
    expect(taskClocked(c.document.toSource(), 'a').single.end, isNotNull);
    await c.setTaskStatus(c.document.blocks.last.id, 'todo');
    expect(taskClocked(c.document.toSource(), 'b').single.end, isNotNull);
    check(c);
  });
  test('editor toggle records repeat occurrence', () {
    final c = editor(
      '#tylog.task(id: "t", text: "Walk", recurrence: "RRULE:FREQ=DAILY")',
    );
    addTearDown(c.dispose);
    c.toggleTask(c.document.blocks.first.id);
    expect(c.document.toSource(), contains('completed: ('));
    expect(taskField(c.document.toSource(), 'status'), 'todo');
    check(c);
  });
}
