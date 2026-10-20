import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/rich_editor.dart';
import 'package:tylog/widgets/fold_store.dart';

const _source =
    '- Ящики.\n'
    '  - #tylog.task(id: "a", text: "A")\n'
    '    - #tylog.task(id: "b", text: "B")\n'
    '  - #tylog.task(id: "c", text: "C")\n\n'
    'После';

void main() {
  tearDown(() => FoldStore.instance = null);

  test('outline measures nested bullets and tasks in visible coordinates', () {
    final document = TyLogDocument.parse(_source);
    final lines = outlineOf(document);

    expect(lines.map((line) => line.text), [
      '• Ящики.',
      '☐ A',
      '☐ B',
      '☐ C',
      '',
      'После',
    ]);
    expect(lines.map((line) => line.depth), [0, 1, 2, 1, 0, 0]);
    expect(lines.map((line) => line.isFoldable), [
      true,
      true,
      false,
      false,
      false,
      false,
    ]);
    expect(lines.last.end, document.visibleText.length);
  });

  test('a heading or paragraph ends a subtree', () {
    final document = TyLogDocument.parse(
      '- root\n  - child\n\n= Heading\n\nparagraph',
    );
    final lines = outlineOf(document);

    expect(lines.map((line) => line.depth), [0, 1, 0, 0, 0, 0]);
    expect(lines.map((line) => line.isFoldable), [
      true,
      false,
      false,
      false,
      false,
      false,
    ]);
    final hidden = hiddenRanges(document, {lines.first.start});
    expect(hidden, [TextRange(start: lines[0].end, end: lines[1].end)]);
  });

  test(
    'nested folds union their descendant ranges and preserve the last line',
    () {
      final document = TyLogDocument.parse(_source);
      final lines = outlineOf(document);
      final hidden = hiddenRanges(document, {lines[0].start, lines[1].start});

      expect(hidden, [TextRange(start: lines[0].end, end: lines[3].end)]);
      expect(hiddenRanges(document, {lines[3].start}), isEmpty);
      expect(lines.last.end, document.visibleText.length);
    },
  );

  test('fold keys are scoped and occurrence-stable', () {
    final document = TyLogDocument.parse(
      '- same\n  - child\n\n- same\n  - child',
    );
    final lines = outlineOf(document);

    expect(
      foldKeyFor('daily.typ', lines[0], lines),
      'outline:daily.typ|• same|0',
    );
    expect(
      foldKeyFor('daily.typ', lines[3], lines),
      'outline:daily.typ|• same|1',
    );
  });

  testWidgets('reading fold changes layout without changing source', (
    tester,
  ) async {
    final dir = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('outline-fold-'),
    ))!;
    addTearDown(() => dir.delete(recursive: true));
    final store = (await tester.runAsync(
      () => FoldStore.open(File('${dir.path}/folds.json')),
    ))!;
    FoldStore.instance = store;
    final controller = TyLogEditingController(
      source: _source,
      onSourceChanged: (_) {},
      onError: (_) {},
      onProtectedTap: (_) {},
      foldScope: 'daily.typ',
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TyLogReadView(source: _source, foldScope: 'daily.typ'),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    final lines = outlineOf(controller.document);
    final paragraph = tester.renderObject<RenderParagraph>(
      find.byType(RichText).first,
    );
    final box = paragraph
        .getBoxesForSelection(
          const TextSelection(baseOffset: 0, extentOffset: 1),
        )
        .single
        .toRect();
    final before = paragraph.size.height;
    await tester.tapAt(paragraph.localToGlobal(box.center));
    await tester.pump();
    expect(store.isFolded(foldKeyFor('daily.typ', lines.first, lines)), isTrue);
    final after = tester.getSize(find.byType(RichText)).height;
    expect(after, lessThan(before));
    expect(controller.document.toSource(), _source);
    await tester.tapAt(paragraph.localToGlobal(box.center));
    await tester.pump();
    expect(tester.getSize(find.byType(RichText)).height, before);
  });

  testWidgets('editor folds from the bullet caret and unfolds before editing', (
    tester,
  ) async {
    final dir = await tester.runAsync(
      () => Directory.systemTemp.createTemp('outline-editor-fold-'),
    );
    addTearDown(() => dir!.delete(recursive: true));
    FoldStore.instance = await tester.runAsync(
      () => FoldStore.open(File('${dir!.path}/folds.json')),
    );
    final controller = TyLogEditingController(
      source: _source,
      onSourceChanged: (_) {},
      onError: (_) {},
      onProtectedTap: (_) {},
      foldScope: 'daily.typ',
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TyLogRichEditor(controller: controller, onInsert: () async {}),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final editable = tester.allRenderObjects.whereType<RenderEditable>().single;
    final caret = editable.getLocalRectForCaret(const TextPosition(offset: 0));
    final sourceBefore = controller.document.toSource();
    await tester.tapAt(editable.localToGlobal(caret.center));
    await tester.pump();
    final lines = outlineOf(controller.document);
    expect(
      FoldStore.instance!.isFolded(foldKeyFor('daily.typ', lines.first, lines)),
      isTrue,
    );
    expect(controller.text, controller.document.visibleText);
    expect(controller.document.toSource(), sourceBefore);

    controller.selection = TextSelection.collapsed(offset: lines[1].start + 2);
    await tester.pump();
    expect(
      FoldStore.instance!.isFolded(foldKeyFor('daily.typ', lines.first, lines)),
      isFalse,
    );

    final parentText = controller.text;
    controller.value = TextEditingValue(
      text: parentText.replaceRange(2, 2, 'X'),
      selection: const TextSelection.collapsed(offset: 3),
    );
    expect(controller.document.toSource(), contains('X'));
  });

  test(
    'fold state survives reopening the store and loading a fresh controller',
    () async {
      final dir = await Directory.systemTemp.createTemp('outline-persist-');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/folds.json');
      final first = await FoldStore.open(file);
      final document = TyLogDocument.parse(_source);
      final lines = outlineOf(document);
      final key = foldKeyFor('daily.typ', lines.first, lines);
      await first.toggle(key);
      final reopened = await FoldStore.open(file);
      FoldStore.instance = reopened;
      final controller = TyLogEditingController(
        source: _source,
        onSourceChanged: (_) {},
        onError: (_) {},
        onProtectedTap: (_) {},
        foldScope: 'daily.typ',
      );
      addTearDown(controller.dispose);
      expect(reopened.isFolded(key), isTrue);
      expect(controller.foldedParentLineStarts, contains(lines.first.start));
      controller.loadSource(_source);
      expect(controller.foldedParentLineStarts, contains(lines.first.start));
    },
  );

  testWidgets('no store or scope leaves the rendered span text unchanged', (
    tester,
  ) async {
    final controller = TyLogEditingController(
      source: _source,
      onSourceChanged: (_) {},
      onError: (_) {},
      onProtectedTap: (_) {},
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TyLogRichEditor(controller: controller, onInsert: () async {}),
        ),
      ),
    );
    await tester.pump();
    final span = controller.buildTextSpan(
      context: tester.element(find.byType(EditableText)),
      withComposing: false,
    );
    expect(span.toPlainText(), controller.text);
    expect(span.toPlainText(), isNot(contains('▸')));
  });

  testWidgets('a hidden child that is itself a parent shows no bullet', (
    tester,
  ) async {
    final dir = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('outline-nested-'),
    ))!;
    addTearDown(() => dir.delete(recursive: true));
    FoldStore.instance = (await tester.runAsync(
      () => FoldStore.open(File('${dir.path}/fold_state.json')),
    ))!;
    final controller = TyLogEditingController(
      source: '- root\n  - mid\n    - leaf\n- after',
      onSourceChanged: (_) {},
      onError: (_) {},
      onProtectedTap: (_) {},
      foldScope: 'n.typ',
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TyLogRichEditor(controller: controller, onInsert: () async {}),
        ),
      ),
    );
    final lines = outlineOf(controller.document);
    await tester.runAsync(
      () => FoldStore.instance!.toggle(foldKeyFor('n.typ', lines.first, lines)),
    );
    await tester.pump();
    final hidden = hiddenRanges(controller.document, {lines.first.start});
    final span = controller.buildTextSpan(
      context: tester.element(find.byType(EditableText)),
      withComposing: false,
    );
    var at = 0;
    final visibleGlyphs = <int>[];
    span.visitChildren((child) {
      if (child is TextSpan && child.text != null) {
        final text = child.text!;
        final tiny = (child.style?.fontSize ?? 14) < 1;
        for (var i = 0; i < text.length; i++) {
          if ((text[i] == '•' || text[i] == '▸') && !tiny) {
            visibleGlyphs.add(at + i);
          }
        }
        at += text.length;
      } else if (child is WidgetSpan) {
        at += 1;
      }
      return true;
    });
    expect(
      visibleGlyphs.where(
        (g) => hidden.any((r) => r.start <= g && g < r.end),
      ),
      isEmpty,
    );
  });

  test('search reveal keeps offsets after a folded subtree', () {
    final controller = TyLogEditingController(
      source: _source,
      onSourceChanged: (_) {},
      onError: (_) {},
      onProtectedTap: (_) {},
      foldScope: 'daily.typ',
    );
    addTearDown(controller.dispose);
    final lines = outlineOf(controller.document);
    expect(controller.searchRevealRange('После')?.start, lines.last.start);
  });
}
