import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/rich_editor.dart';

void expectRoundTrip(TyLogEditingController controller, String source) {
  expect(controller.document.toSource(), source);
  final reparsed = TyLogDocument.parse(source);
  expect(reparsed.visibleText, controller.text);
  expect(reparsed.toSource(), source);
}

void main() {
  for (final ordered in [false, true]) {
    testWidgets(
      'Tab nests and Shift-Tab un-nests a ${ordered ? 'numbered' : 'bullet'} item',
      (tester) async {
        final original = ordered ? '+ parent\n+ child' : '- parent\n- child';
        final nested = ordered ? '+ parent\n  + child' : '- parent\n  - child';
        final sources = <String>[];
        final controller = TyLogEditingController(
          source: original,
          onSourceChanged: sources.add,
          onError: (error) => fail('$error'),
          onProtectedTap: (_) {},
        );
        addTearDown(controller.dispose);
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(platform: TargetPlatform.linux),
            home: Scaffold(
              body: TyLogRichEditor(
                controller: controller,
                onInsert: () async {},
              ),
            ),
          ),
        );
        await tester.tap(find.byType(EditableText));
        await tester.pumpAndSettle();
        final caret = controller.text.indexOf('child') + 2;
        controller.selection = TextSelection.collapsed(offset: caret);

        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        expect(sources, [nested]);
        expect(controller.selection.baseOffset, caret + 2);
        expectRoundTrip(controller, nested);
        expect(
          tester
              .widget<EditableText>(find.byType(EditableText))
              .focusNode
              .hasFocus,
          isTrue,
        );

        final dir = Directory.systemTemp.createTempSync('tab_nested_');
        addTearDown(() => dir.deleteSync(recursive: true));
        final file = File('${dir.path}/nested.typ')
          ..writeAsStringSync(sources.last);
        final compiled = Process.runSync('typst', [
          'compile',
          file.path,
          '${dir.path}/nested.pdf',
        ]);
        expect(compiled.exitCode, 0, reason: '${compiled.stderr}');

        await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        await tester.pump();
        expect(sources, [nested, original]);
        expect(controller.selection.baseOffset, caret);
        expectRoundTrip(controller, original);

        controller.undo();
        expectRoundTrip(controller, nested);
        controller.redo();
        expectRoundTrip(controller, original);
      },
    );
  }

  testWidgets('mobile toolbar indents and outdents the current list item', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final sources = <String>[];
    final controller = TyLogEditingController(
      source: '- parent\n- child',
      onSourceChanged: sources.add,
      onError: (error) => fail('$error'),
      onProtectedTap: (_) {},
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.android),
        home: Scaffold(
          body: TyLogRichEditor(controller: controller, onInsert: () async {}),
        ),
      ),
    );
    await tester.tap(find.byType(EditableText));
    await tester.pumpAndSettle();
    controller.selection = TextSelection.collapsed(
      offset: controller.text.indexOf('child'),
    );
    final toolbar = find.descendant(
      of: find.byType(ListView),
      matching: find.byType(Scrollable),
    );
    await tester.scrollUntilVisible(
      find.byTooltip('Indent'),
      200,
      scrollable: toolbar,
    );
    await tester.tap(find.byTooltip('Indent'));
    await tester.pump();
    expect(sources.last, '- parent\n  - child');
    expectRoundTrip(controller, sources.last);

    await tester.scrollUntilVisible(
      find.byTooltip('Outdent'),
      200,
      scrollable: toolbar,
    );
    await tester.tap(find.byTooltip('Outdent'));
    await tester.pump();
    expect(sources, ['- parent\n  - child', '- parent\n- child']);
    expectRoundTrip(controller, sources.last);
    expect(
      tester.widget<EditableText>(find.byType(EditableText)).focusNode.hasFocus,
      isTrue,
    );
  });

  for (final (original, nested, target) in [
    ('paragraph', '  paragraph', 'paragraph'),
    ('first\nsecond', 'first\n  second', 'second'),
    ('', '  ', ''),
    ('- parent\ncontinuation', '- parent\n  - continuation', 'continuation'),
    (
      '+ parent\ncontinuation\n+ sibling',
      '+ parent\n  - continuation\n+ sibling',
      'continuation',
    ),
  ]) {
    test(
      'indent/outdent round-trips ${original.isEmpty ? 'an empty paragraph' : original}',
      () {
        final sources = <String>[];
        final controller = TyLogEditingController(
          source: original,
          onSourceChanged: sources.add,
          onError: (error) => fail('$error'),
          onProtectedTap: (_) {},
        );
        addTearDown(controller.dispose);
        controller.selection = TextSelection.collapsed(
          offset: controller.text.indexOf(target),
        );
        controller.indentLine();
        expect(sources, [nested]);
        expectRoundTrip(controller, nested);
        controller.outdentLine();
        // A promoted continuation keeps its list marker when brought back up.
        final outdented = original.contains('continuation')
            ? original.replaceFirst('continuation', '- continuation')
            : original;
        expect(sources.last, outdented);
        expectRoundTrip(controller, outdented);
      },
    );
  }

  test(
    'outdent at the margin and indentation of protected blocks are no-ops',
    () {
      for (final source in [
        'paragraph',
        '- item',
        '#table([protected])',
        '#tylog.task(id: "t", text: "task")',
      ]) {
        final sources = <String>[];
        final controller = TyLogEditingController(
          source: source,
          onSourceChanged: sources.add,
          onError: (error) => fail('$error'),
          onProtectedTap: (_) {},
        );
        addTearDown(controller.dispose);
        controller.selection = const TextSelection.collapsed(offset: 0);
        controller.outdentLine();
        if (controller.document.blocks.single.style ==
                TyLogBlockStyle.protected ||
            controller.document.blocks.single.style ==
                TyLogBlockStyle.taskLine) {
          controller.indentLine();
        }
        expect(sources, isEmpty);
        expect(controller.canUndo, isFalse);
        expectRoundTrip(controller, source);
      }
    },
  );
}
