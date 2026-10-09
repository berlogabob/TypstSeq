import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/rich_editor.dart';
import 'package:tylog/vault.dart';
import 'package:tylog/workspace_controller.dart';
import 'package:tylog/task_scheduler.dart' show TaskScheduler;
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

  tearDownAll(() {
    final dir = Directory('.dart_tool/task_typing_test');
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  for (final leave in ['caret', 'text']) {
    testWidgets('repeat popup closes on $leave leaving its task', (
      tester,
    ) async {
      final c = editor(
        '#tylog.task(id: "a", text: "First")\n\n#tylog.task(id: "b", text: "Second")',
      );
      addTearDown(c.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TyLogRichEditor(controller: c, onInsert: () async {}),
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('rich-journal-editor')));
      final end = c.text.indexOf('First') + 5;
      c.value = TextEditingValue(
        text: c.text.replaceRange(end, end, ' /repeat'),
        selection: TextSelection.collapsed(offset: end + 8),
      );
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(find.text('daily'), findsOneWidget);
      if (leave == 'caret') {
        c.selection = TextSelection.collapsed(offset: c.text.length);
      } else {
        final caret = c.selection.extentOffset;
        c.value = TextEditingValue(
          text: c.text.replaceRange(caret, caret, ' extra text'),
          selection: TextSelection.collapsed(offset: caret + 11),
        );
      }
      await tester.pump();
      expect(find.text('daily'), findsNothing);
      expect(c.document.toSource(), isNot(contains('recurrence:')));
      check(c);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  for (final field in ['repeat', 'due', 'scheduled']) {
    testWidgets('$field popup clears only its field', (tester) async {
      final c = editor(
        '#tylog.task(id: "t", text: "Call", due: "2026-10-10", scheduled: "2026-10-09", recurrence: "RRULE:FREQ=DAILY", properties: ("custom": "keep"))',
      );
      addTearDown(c.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TyLogRichEditor(controller: c, onInsert: () async {}),
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('rich-journal-editor')));
      type(c, '${c.text} /$field');
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(find.text('none'), findsOneWidget);
      await tester.tap(find.text('none'));
      await tester.pump();
      final out = c.document.toSource();
      final key = field == 'repeat' ? 'recurrence' : field;
      expect(out, contains('$key: none'));
      for (final entry in {
        'due': '2026-10-10',
        'scheduled': '2026-10-09',
        'recurrence': 'RRULE:FREQ=DAILY',
      }.entries) {
        if (entry.key != key) expect(taskField(out, entry.key), entry.value);
      }
      expect(out, contains('properties: ("custom": "keep")'));
      check(c);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  for (final rawEnter in [false, true]) {
    testWidgets(
      'A24 stale reload between Enter and typing (${rawEnter ? "keys" : "IME"})',
      (tester) async {
        const source = '#tylog.task(id: "t", text: "confirm")\n';
        final workspace = WorkspaceController(taskScheduler: TaskScheduler());
        addTearDown(workspace.dispose);
        final dir = await tester.runAsync(
          () => Directory.systemTemp.createTemp('a24_reload_'),
        );
        addTearDown(() => dir!.deleteSync(recursive: true));
        workspace.vault = Vault(dir!);
        await tester.runAsync(
          () => workspace.vault!.storage.writeText('probe.typ', source),
        );
        workspace.replaceNote('probe.typ', source);
        final c = TyLogEditingController(
          source: source,
          onSourceChanged: workspace.edit,
          onError: (e) => fail('$e'),
          onProtectedTap: (_) {},
          nextTaskId: (_) async => 'new-task',
        );
        addTearDown(c.dispose);
        // Hold delivery of an external read until the user has pressed Enter.
        final snapshot = await tester.runAsync(
          () => workspace.readNoteSnapshot('probe.typ'),
        );
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: TyLogRichEditor(controller: c, onInsert: () async {}),
            ),
          ),
        );
        await tester.tap(find.byKey(const Key('rich-journal-editor')));
        c.selection = TextSelection.collapsed(offset: c.text.length);
        final before = c.value;
        if (rawEnter) await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        if (c.text == before.text) {
          tester.testTextInput.updateEditingValue(
            TextEditingDeltaInsertion(
              oldText: before.text,
              textInserted: '\n',
              insertionOffset: before.selection.extentOffset,
              selection: TextSelection.collapsed(
                offset: before.selection.extentOffset + 1,
              ),
              composing: TextRange.empty,
            ).apply(before),
          );
        }
        await tester.pump();
        if (workspace.adoptNoteRead('probe.typ', snapshot!)) {
          c.loadSource(snapshot.source);
        }
        final v = c.value;
        tester.testTextInput.updateEditingValue(
          TextEditingDeltaInsertion(
            oldText: v.text,
            textInserted: 'zzprobe',
            insertionOffset: v.selection.extentOffset,
            selection: TextSelection.collapsed(
              offset: v.selection.extentOffset + 7,
            ),
            composing: TextRange.empty,
          ).apply(v),
        );
        await tester.pump();
        expect(c.text, endsWith('☐ zzprobe'));
        expect(c.currentTaskBlockId, isNotNull);
        expect(workspace.source, contains('text: "zzprobe"'));
        workspace.cancelPendingWork();
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  for (final rawKeys in [false, true]) {
    for (final due in ['', ', due: "2026-10-09"']) {
      testWidgets(
        'A24 empty task demotes and removes (${rawKeys ? "keys" : "IME"}$due)',
        (tester) async {
          final c = editor('#tylog.task(id: "t", text: "confirm")\n');
          addTearDown(c.dispose);
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: TyLogRichEditor(controller: c, onInsert: () async {}),
              ),
            ),
          );
          await tester.tap(find.byKey(const Key('rich-journal-editor')));
          c.selection = TextSelection.collapsed(offset: c.text.length);
          final beforeEnter = c.value;
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          if (c.text == beforeEnter.text) {
            tester.testTextInput.updateEditingValue(
              TextEditingDeltaInsertion(
                oldText: beforeEnter.text,
                textInserted: '\n',
                insertionOffset: beforeEnter.selection.extentOffset,
                selection: TextSelection.collapsed(
                  offset: beforeEnter.selection.extentOffset + 1,
                ),
                composing: TextRange.empty,
              ).apply(beforeEnter),
            );
          }
          await tester.pump();
          final old = c.value;
          final insertion = TextEditingDeltaInsertion(
            oldText: old.text,
            textInserted: 'zzprobe',
            insertionOffset: old.selection.extentOffset,
            selection: TextSelection.collapsed(
              offset: old.selection.extentOffset + 7,
            ),
            composing: TextRange.empty,
          );
          // EditableText uses full-state TextInput messages; apply the IME delta to that state.
          tester.testTextInput.updateEditingValue(insertion.apply(old));
          await tester.pump();
          if (due.isNotEmpty) c.setCurrentTaskFields(due: '2026-10-09');
          Future<void> backspace() async {
            final v = c.value;
            if (rawKeys) {
              await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
            }
            if (!rawKeys || c.text == v.text) {
              final end = v.selection.extentOffset;
              tester.testTextInput.updateEditingValue(
                TextEditingDeltaDeletion(
                  oldText: v.text,
                  deletedRange: TextRange(start: end - 1, end: end),
                  selection: TextSelection.collapsed(offset: end - 1),
                  composing: TextRange.empty,
                ).apply(v),
              );
            }
            await tester.pump();
          }

          for (var i = 0; i < 7; i++) {
            await backspace();
          }
          expect(c.text, endsWith('☐ '));
          final emptySource = c.document.toSource();
          await backspace();
          expect(c.currentTaskBlockId, isNull);
          expect(c.text, endsWith('\n\n'));
          c.undo();
          expect(c.document.toSource(), emptySource);
          c.redo();
          await backspace();
          expect(
            c.document.toSource(),
            '#tylog.task(id: "t", text: "confirm")\n',
          );
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );
    }
  }

  testWidgets('A24 Enter text due fri keeps the new task glyph', (
    tester,
  ) async {
    final c = editor(
      '#tylog.task(id: "t", text: "confirm", priority: "high")\n',
    );
    addTearDown(c.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TyLogRichEditor(controller: c, onInsert: () async {}),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('rich-journal-editor')));
    c.selection = TextSelection.collapsed(offset: c.text.length);
    final imeText = '${c.text}\n';
    type(c, imeText);
    await tester.pump(const Duration(seconds: 1));
    tester.testTextInput.updateEditingValue(
      TextEditingValue(
        text: '${imeText}zzprobe',
        selection: TextSelection.collapsed(offset: imeText.length + 7),
      ),
    );
    await tester.pump(const Duration(seconds: 6));
    expect(c.text, endsWith('☐ zzprobe'));
    expect(c.currentTaskBlockId, isNotNull);
    type(c, '${c.text} /d');
    await tester.pump();
    expect(find.byKey(const Key('autocomplete-task-due')), findsOneWidget);
    type(c, '${c.text}ue');
    await tester.pump();
    type(c, '${c.text}\n');
    await tester.pump();
    await tester.enterText(find.byKey(const Key('task-date-input')), 'fri');
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    final call = locateTypstCalls(
      c.document.toSource(),
      names: const {'tylog.task'},
    ).last.source;
    expect(taskField(call, 'text'), 'zzprobe');
    final now = DateTime.now();
    final days = (DateTime.friday - now.weekday + 7) % 7;
    final friday = DateTime(
      now.year,
      now.month,
      now.day + (days == 0 ? 7 : days),
    );
    expect(taskField(call, 'due'), isoDay(friday));
    expect(c.text, endsWith('☐ zzprobe'));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test('A24 task add delete cycles keep one EOF newline', () async {
    final c = editor('#tylog.task(id: "t", text: "confirm")\n');
    addTearDown(c.dispose);
    void insert(String text) {
      final caret = c.selection.extentOffset;
      c.value = TextEditingValue(
        text: c.text.replaceRange(caret, caret, text),
        selection: TextSelection.collapsed(offset: caret + text.length),
      );
    }

    for (var i = 0; i < 3; i++) {
      c.selection = TextSelection.collapsed(
        offset: c.document.blockRanges.first.end,
      );
      insert('\n');
      await Future<void>.delayed(Duration.zero);
      insert('zzprobe');
      expect(c.document.toSource(), endsWith(')\n'));
      expect(c.document.toSource(), isNot(contains('\n\n\n')));
      final caret = c.selection.extentOffset;
      c.value = TextEditingValue(
        text: c.text.replaceRange(caret - 7, caret, ''),
        selection: TextSelection.collapsed(offset: caret - 7),
      );
      insert('\n'); // Enter on an empty task demotes it.
      expect(c.document.toSource(), '#tylog.task(id: "t", text: "confirm")\n');
    }
  });

  testWidgets('A24 real font task spacing equals paragraphs at 420px', (
    tester,
  ) async {
    final loader = FontLoader('A24Real')
      ..addFont(
        Future.value(
          ByteData.sublistView(
            File('docs/fonts/InterVariable.ttf').readAsBytesSync(),
          ),
        ),
      );
    await loader.load();
    tester.view.physicalSize = const Size(420, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    Future<double> spacing(String source) async {
      final c = editor(source);
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(fontFamily: 'A24Real'),
          home: Scaffold(
            body: TyLogRichEditor(controller: c, onInsert: () async {}),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final render = tester
          .state<EditableTextState>(find.byType(EditableText))
          .renderEditable;
      final first = render.getLocalRectForCaret(
        TextPosition(offset: c.text.indexOf('First')),
      );
      final second = render.getLocalRectForCaret(
        TextPosition(offset: c.text.indexOf('Second')),
      );
      final distance = second.top - first.top;
      await tester.pumpWidget(const SizedBox.shrink());
      c.dispose();
      return distance;
    }

    final normal = await spacing('First\n\nSecond');
    for (final fields in ['', ', priority: "high"']) {
      expect(
        await spacing(
          '#tylog.task(id: "a", text: "First"$fields)\n\n#tylog.task(id: "b", text: "Second")',
        ),
        closeTo(normal, .1),
        reason: fields,
      );
    }
    expect(
      await spacing(
        '#tylog.task(id: "a", text: "First call bank tomorrow", priority: "high", due: "2026-10-09", scheduled: "2026-10-10", recurrence: "RRULE:FREQ=WEEKLY")\n\n#tylog.task(id: "b", text: "Second")',
      ),
      greaterThan(normal),
    );
  });

  testWidgets('A24 popups show rows above keyboard and preserve date caret', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(420, 800);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(top: 40);
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(tester.view.reset);
    final c = editor('#tylog.task(id: "t", text: "Call", priority: "high")');
    addTearDown(c.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.only(top: 200),
            child: TyLogRichEditor(controller: c, onInsert: () async {}),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('task-chip-t-priority')));
    await tester.pump();
    final popup = tester.getRect(find.byKey(const Key('autocomplete-popup')));
    final first = tester.getRect(
      find.byKey(const Key('autocomplete-task-urgent')),
    );
    final last = tester.getRect(find.byKey(const Key('autocomplete-task-c')));
    expect(first.top, popup.top);
    expect(last.bottom, lessThanOrEqualTo(popup.bottom));
    await tester.tap(find.byKey(const Key('autocomplete-task-c')));
    await tester.pump();
    type(c, '${c.text} /due');
    await tester.pump();
    final command = tester.getRect(
      find.byKey(const Key('autocomplete-task-due')),
    );
    final commandPopup = tester.getRect(
      find.byKey(const Key('autocomplete-popup')),
    );
    expect(command.top, commandPopup.top);
    expect(command.bottom, lessThanOrEqualTo(commandPopup.bottom));
    expect(commandPopup.bottom, lessThanOrEqualTo(500));
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    await tester.enterText(find.byKey(const Key('task-date-input')), 'fri');
    await tester.pump();
    final candidate = find.descendant(
      of: find.byKey(const Key('autocomplete-popup')),
      matching: find.byType(ListTile),
    );
    expect(candidate, findsWidgets);
    expect(
      tester.getRect(candidate.first).bottom,
      lessThanOrEqualTo(
        tester.getRect(find.byKey(const Key('autocomplete-popup'))).bottom,
      ),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(c.selection.extentOffset, c.text.length);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('A24 consecutive tasks reserve only chip height', (tester) async {
    final c = editor(
      '#tylog.task(id: "a", text: "First", priority: "urgent")\n#tylog.task(id: "b", text: "Second")',
    );
    addTearDown(c.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TyLogRichEditor(controller: c, onInsert: () async {}),
        ),
      ),
    );
    await tester.pump();
    final editable = tester
        .state<EditableTextState>(find.byType(EditableText))
        .renderEditable;
    final first = editable.getLocalRectForCaret(const TextPosition(offset: 0));
    final second = editable.getLocalRectForCaret(
      TextPosition(offset: c.text.indexOf('Second')),
    );
    expect(second.top - first.top, lessThan(100));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('A24 scrolled-out task strip cannot paint below the divider', (
    tester,
  ) async {
    final c = editor(
      '#tylog.task(id: "a", text: "First", priority: "urgent")\n${List.filled(30, 'paragraph').join('\n')}',
    );
    addTearDown(c.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              const SizedBox(height: 100),
              const Divider(),
              Expanded(
                child: TyLogRichEditor(controller: c, onInsert: () async {}),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    final textField = tester.widget<TextField>(
      find.byKey(const Key('rich-journal-editor')),
    );
    final field = tester
        .state<EditableTextState>(find.byType(EditableText))
        .renderEditable;
    final end = field.getLocalRectForCaret(
      TextPosition(offset: c.text.indexOf('First') + 5),
    );
    textField.scrollController!.jumpTo(end.bottom + 20);
    await tester.pump();
    final chip = find.byKey(const Key('task-chip-a-priority'));
    final bounds = tester.getRect(chip);
    final editorTop = tester
        .getRect(find.byKey(const Key('rich-journal-editor')))
        .top;
    final point = Offset(bounds.center.dx, editorTop + 2);
    final hits = tester.hitTestOnBinding(point).path;
    final render = tester.renderObject(chip);
    expect(hits.any((hit) => identical(hit.target, render)), isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test('all status glyphs edit, demote, undo, round-trip and compile', () {
    for (final (status, glyph) in [
      ('todo', '☐'),
      ('doing', '◐'),
      ('done', '☑'),
      ('cancelled', '☒'),
    ]) {
      final c = editor('#tylog.task(id: "t", text: "Call", status: "$status")');
      addTearDown(c.dispose);
      expect(c.text, '$glyph Call');
      type(c, '${c.text}!');
      expect(taskField(c.document.toSource(), 'text'), 'Call!');
      check(c);
      c.value = TextEditingValue(
        text: '${glyph}Call!',
        selection: const TextSelection.collapsed(offset: 1),
      );
      expect(c.text, 'Call!');
      c.undo();
      expect(c.text, '$glyph Call!');
      check(c);
    }
  });
  testWidgets('Back closes editor field popup before leaving route', (
    tester,
  ) async {
    final c = editor('#tylog.task(id: "t", text: "Task", priority: "high")');
    addTearDown(c.dispose);
    final nav = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: nav,
        home: const Scaffold(body: Text('Home')),
      ),
    );
    nav.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          body: TyLogRichEditor(controller: c, onInsert: () async {}),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('task-chip-t-priority')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('autocomplete-popup')), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('autocomplete-popup')), findsNothing);
    expect(find.byType(TyLogRichEditor), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Home'), findsOneWidget);
  });

  testWidgets('task strip chips open the inline fields at 320px without overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final c = editor(
      '#tylog.task(id: "t", text: "Call bank with a long task line", priority: "high", due: "${isoDay(DateTime.now())}", scheduled: "${isoDay(DateTime.now().add(const Duration(days: 1)))}", recurrence: "RRULE:FREQ=WEEKLY")\nNext paragraph',
    );
    addTearDown(c.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TyLogRichEditor(controller: c, onInsert: () async {}),
        ),
      ),
    );
    await tester.pump();
    final field = find.byKey(const Key('rich-journal-editor'));
    final editable = tester
        .state<EditableTextState>(find.byType(EditableText))
        .renderEditable;
    final next = editable.getLocalRectForCaret(
      TextPosition(offset: c.text.indexOf('Next paragraph')),
    );
    final nextTop = editable.localToGlobal(next.topLeft).dy;
    final stripBottom = tester
        .getRect(find.byKey(const Key('task-chip-t-repeat')))
        .bottom;
    expect(stripBottom, lessThanOrEqualTo(nextTop));
    for (final command in ['priority', 'due', 'scheduled', 'repeat']) {
      final chip = find.byKey(Key('task-chip-t-$command'));
      expect(chip, findsOneWidget);
      await tester.tap(chip);
      await tester.pump();
      expect(find.byKey(const Key('autocomplete-popup')), findsOneWidget);
      if (command == 'priority') {
        await tester.tap(find.byKey(const Key('autocomplete-task-c')));
      } else if (command == 'repeat') {
        await tester.tap(find.text('daily'));
      } else {
        expect(find.byKey(const Key('task-date-input')), findsOneWidget);
        await tester.enterText(
          find.byKey(const Key('task-date-input')),
          'tomorrow',
        );
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      }
      await tester.pump();
      expect(tester.takeException(), isNull);
      check(c);
    }
    c.loadSource(
      '#tylog.task(id: "t", text: "Call", status: "cancelled", due: "2020-10-15")',
    );
    await tester.pump();
    final dueLabel = tester.widget<Text>(
      find.descendant(
        of: find.byKey(const Key('task-chip-t-due')),
        matching: find.byType(Text),
      ),
    );
    expect(dueLabel.data, '15 Oct');
    expect(
      dueLabel.style!.color,
      Theme.of(tester.element(field)).colorScheme.error,
    );
    final span = c.buildTextSpan(
      context: tester.element(field),
      style: Theme.of(tester.element(field)).textTheme.bodyLarge,
      withComposing: false,
    );
    expect(
      (span.children!.first as TextSpan).style!.decoration,
      TextDecoration.lineThrough,
    );
    c.loadSource('#tylog.task(id: "t", text: "Call")');
    await tester.pump();
    for (final field in ['priority', 'due', 'scheduled', 'repeat', 'time']) {
      expect(find.byKey(Key('task-chip-t-$field')), findsNothing);
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('Doing strip ticks total time without moving text or timer', (
    tester,
  ) async {
    final start = DateTime.now()
        .toUtc()
        .subtract(const Duration(seconds: 5))
        .toIso8601String();
    final c = editor(
      '#tylog.task(id: "t", text: "Call", status: "doing", clocked: ((start: "$start", end: none),))',
    );
    addTearDown(c.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TyLogRichEditor(controller: c, onInsert: () async {}),
        ),
      ),
    );
    await tester.pump();
    final chip = find.byKey(const Key('task-chip-t-time'));
    expect(chip, findsOneWidget);
    final rect = tester.getRect(chip);
    final text = c.text;
    final editable = tester
        .state<EditableTextState>(find.byType(EditableText))
        .renderEditable;
    final caret = editable.getLocalRectForCaret(
      TextPosition(offset: c.text.length),
    );
    final before = tester
        .widget<Text>(find.descendant(of: chip, matching: find.byType(Text)))
        .data;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 1100)),
    );
    await tester.pump(const Duration(seconds: 2));
    expect(
      tester
          .widget<Text>(find.descendant(of: chip, matching: find.byType(Text)))
          .data,
      isNot(before),
    );
    expect(tester.getRect(chip), rect);
    expect(c.text, text);
    expect(
      editable.getLocalRectForCaret(TextPosition(offset: c.text.length)),
      caret,
    );
    c.loadSource(
      '#tylog.task(id: "t", text: "Call", clocked: ((start: "2026-10-01T10:00:00Z", end: "2026-10-01T10:02:00Z"),))',
    );
    await tester.pump();
    expect(
      tester
          .widget<Text>(find.descendant(of: chip, matching: find.byType(Text)))
          .data,
      '02:00',
    );
    c.loadSource('#tylog.task(id: "t", text: "Call")');
    await tester.pump();
    expect(chip, findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });
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
      expect(
        c.text,
        '${const {'done': '☑', 'doing': '◐', 'cancel': '☒'}[command] ?? '☐'} Call bank',
      );
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
      expect(c.selection.extentOffset, c.text.length);
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
      expect(c.text, '◐ Call');
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
