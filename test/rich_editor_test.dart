import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/rich_editor.dart';

const _source = '''#import "/_system/tylog.typ" as tylog
#show: tylog.note.with(
  id: "2026-07-07",
  title: "2026-07-07",
  kind: "daily",
  date: "2026-07-07",
  tags: ("journal",),
)

= 2026-07-07

привет, как дела?

#strong[Bold] and #emph[italic]

#custom()[Keep exactly]
''';

void main() {
  test(
    'rich document hides generated title and preserves unchanged source',
    () {
      final document = TyLogDocument.parse(_source);

      expect(document.visibleText, startsWith('привет, как дела?'));
      expect(document.visibleText, isNot(contains('= 2026-07-07')));
      expect(document.visibleText, contains('\uFFFC'));
      expect(document.toSource(), _source);
    },
  );

  test('editing one rich block preserves protected source byte-for-byte', () {
    final document = TyLogDocument.parse(_source);
    final end = document.visibleText.indexOf('?') + 1;

    document.replace(end, end, ' Хорошо.');
    final saved = document.toSource();

    expect(saved, contains('привет, как дела? Хорошо.'));
    expect(saved, contains('#custom()[Keep exactly]'));
    expect(TyLogDocument.parse(saved).visibleText, document.visibleText);
  });

  test('controller applies live bold and supports undo and redo', () {
    final saved = <String>[];
    final errors = <Object>[];
    final controller = TyLogEditingController(
      source: _source,
      onSourceChanged: saved.add,
      onError: errors.add,
      onProtectedTap: (_) {},
    );
    addTearDown(controller.dispose);
    const word = 'привет';
    controller.selection = const TextSelection(
      baseOffset: 0,
      extentOffset: word.length,
    );

    controller.toggleBold();
    expect(saved.last, contains('#strong[привет]'));
    expect(errors, isEmpty);

    controller.undo();
    expect(saved.last, _source);
    controller.redo();
    expect(saved.last, contains('#strong[привет]'));
  });

  test(
    'IME composition renders immediately and commits once with one undo',
    () {
      final saved = <String>[];
      final controller = TyLogEditingController(
        source: _source,
        onSourceChanged: saved.add,
        onError: (error) => fail('$error'),
        onProtectedTap: (_) {},
      );
      addTearDown(controller.dispose);
      final old = controller.text;

      controller.value = TextEditingValue(
        text: old.replaceRange(0, 6, 'здрав'),
        selection: const TextSelection.collapsed(offset: 5),
        composing: const TextRange(start: 0, end: 5),
      );
      expect(controller.text, startsWith('здрав'));
      expect(saved, isEmpty);

      controller.value = TextEditingValue(
        text: old.replaceRange(0, 6, 'здравствуй'),
        selection: const TextSelection.collapsed(offset: 10),
        composing: const TextRange(start: 0, end: 10),
      );

      expect(controller.text, startsWith('здравствуй'));
      expect(controller.value.composing, const TextRange(start: 0, end: 10));
      expect(saved, isEmpty);

      controller.value = controller.value.copyWith(
        selection: const TextSelection.collapsed(offset: 10),
        composing: TextRange.empty,
      );

      expect(saved, hasLength(1));
      expect(saved.single, contains('здравствуй, как дела?'));
      expect(controller.selection, const TextSelection.collapsed(offset: 10));
      controller.undo();
      expect(controller.text, old);
    },
  );

  test('Gboard suggestion replacement does not leave ghost characters', () {
    final saved = <String>[];
    final controller = TyLogEditingController(
      source: 'список ',
      onSourceChanged: saved.add,
      onError: (error) => fail('$error'),
      onProtectedTap: (_) {},
    );
    addTearDown(controller.dispose);

    controller.value = const TextEditingValue(
      text: 'список м',
      selection: TextSelection.collapsed(offset: 8),
      composing: TextRange(start: 7, end: 8),
    );
    controller.value = const TextEditingValue(
      text: 'список мир',
      selection: TextSelection.collapsed(offset: 10),
      composing: TextRange(start: 7, end: 10),
    );
    controller.value = const TextEditingValue(
      text: 'список мира',
      selection: TextSelection.collapsed(offset: 11),
    );

    expect(controller.text, 'список мира');
    expect(saved, ['список мира']);
    controller.undo();
    expect(controller.text, 'список ');
  });

  test('rapid trailing Enters are visible and serialize immediately', () {
    final saved = <String>[];
    final controller = TyLogEditingController(
      source: 'строка',
      onSourceChanged: saved.add,
      onError: (error) => fail('$error'),
      onProtectedTap: (_) {},
    );
    addTearDown(controller.dispose);

    controller.value = const TextEditingValue(
      text: 'строка\n',
      selection: TextSelection.collapsed(offset: 7),
    );
    expect(controller.text, 'строка\n');
    expect(saved.single, 'строка\n');

    controller.value = const TextEditingValue(
      text: 'строка\n\n',
      selection: TextSelection.collapsed(offset: 8),
    );
    expect(controller.text, 'строка\n\n');
    expect(saved.last, 'строка\n\n');

    controller.value = const TextEditingValue(
      text: 'строка\n\nм',
      selection: TextSelection.collapsed(offset: 9),
      composing: TextRange(start: 8, end: 9),
    );
    expect(controller.text, 'строка\n\nм');
    controller.value = controller.value.copyWith(composing: TextRange.empty);
    expect(saved.last, 'строка\n\nм');
  });

  test('collapsed Bold styles subsequently typed text', () {
    String? saved;
    final controller = TyLogEditingController(
      source: _source,
      onSourceChanged: (value) => saved = value,
      onError: (error) => fail('$error'),
      onProtectedTap: (_) {},
    );
    addTearDown(controller.dispose);
    controller.selection = const TextSelection.collapsed(offset: 0);

    controller.toggleBold();
    controller.value = controller.value.copyWith(
      text: 'Да ${controller.text}',
      selection: const TextSelection.collapsed(offset: 3),
    );

    expect(saved, contains('#strong[Да ]привет'));
  });

  test('Typst shorthand and lists render richly and serialize safely', () {
    final document = TyLogDocument.parse('*bold* and _italic_\n\n- one\n- two');
    expect(document.visibleText, 'bold and italic\n\n• one\n• two');

    final one = document.visibleText.indexOf('one');
    document.replace(one, one + 3, 'ONE');

    expect(document.toSource(), '*bold* and _italic_\n\n- ONE\n- two');
  });

  test('deleting a protected card removes the complete source node', () {
    final controller = TyLogEditingController(
      source: _source,
      onSourceChanged: (_) {},
      onError: (error) => fail('$error'),
      onProtectedTap: (_) {},
    );
    addTearDown(controller.dispose);
    final card = controller.text.indexOf('\uFFFC');

    controller.value = controller.value.copyWith(
      text: controller.text.replaceRange(card, card + 1, ''),
      selection: TextSelection.collapsed(offset: card),
    );

    expect(controller.document.toSource(), isNot(contains('#custom()')));
  });

  test('failed source validation refuses to emit destructive output', () {
    final document = TyLogDocument.parse(_source);
    final block = document.blocks.first;
    block
      ..parts.add(
        TyLogInline.atom(source: '#broken[', label: 'Broken', id: 'broken'),
      )
      ..dirty = true;

    expect(document.toSource, throwsFormatException);
  });

  test('copy and paste inside TyLog retains rich formatting', () async {
    String? saved;
    final controller = TyLogEditingController(
      source: _source,
      onSourceChanged: (value) => saved = value,
      onError: (error) => fail('$error'),
      onProtectedTap: (_) {},
    );
    addTearDown(controller.dispose);
    final bold = controller.text.indexOf('Bold');
    controller.selection = TextSelection(
      baseOffset: bold,
      extentOffset: bold + 4,
    );
    await controller.copySelection();
    final target = controller.text.indexOf('italic') + 'italic'.length;
    controller.selection = TextSelection.collapsed(offset: target);

    await controller.paste();

    expect(saved, contains('#emph[italic]#strong[Bold]'));
  });

  testWidgets('rich field renders protected source as a card', (tester) async {
    String? opened;
    final controller = TyLogEditingController(
      source: _source,
      onSourceChanged: (_) {},
      onError: (error) => fail('$error'),
      onProtectedTap: (id) => opened = id,
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TyLogRichEditor(controller: controller, onInsert: () {}),
        ),
      ),
    );

    expect(find.text('Custom Typst'), findsOneWidget);
    await tester.tap(find.text('Custom Typst'));
    expect(opened, isNotNull);
  });

  testWidgets('format toolbar tap keeps focus and applies bold', (
    tester,
  ) async {
    String? saved;
    final controller = TyLogEditingController(
      source: _source,
      onSourceChanged: (value) => saved = value,
      onError: (error) => fail('$error'),
      onProtectedTap: (_) {},
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TyLogRichEditor(controller: controller, onInsert: () {}),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('rich-journal-editor')));
    await tester.pump();
    controller.selection = const TextSelection(baseOffset: 0, extentOffset: 6);

    await tester.tap(find.byTooltip('Bold'));
    await tester.pump();

    expect(saved, contains('#strong[привет]'));
    expect(find.byTooltip('Bold'), findsOneWidget);
  });
}
