import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/controlled_editor.dart';
import 'package:tylog/rich_editor.dart';

final _tinyPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAC0lEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
);

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
    'constructor redirect still parses the source exactly once effectively '
    '(document and displayed text agree)',
    () {
      final controller = TyLogEditingController(
        source: _source,
        onSourceChanged: (_) {},
        onError: (error) => fail('$error'),
        onProtectedTap: (_) {},
      );
      addTearDown(controller.dispose);

      final expected = TyLogDocument.parse(_source).visibleText;
      expect(controller.text, expected);
      expect(controller.document.visibleText, expected);
      expect(controller.document.visibleText, controller.text);
    },
  );

  test('heading, list, and task actions work on an empty document', () {
    TyLogEditingController controller(List<String> saved) =>
        TyLogEditingController(
          source: '',
          onSourceChanged: saved.add,
          onError: (error) => fail('$error'),
          onProtectedTap: (_) {},
        );

    final headingSaved = <String>[];
    final heading = controller(headingSaved);
    addTearDown(heading.dispose);
    heading.setHeading();
    expect(headingSaved.last, startsWith('='));

    final listSaved = <String>[];
    final list = controller(listSaved);
    addTearDown(list.dispose);
    list.setBulletList();
    expect(listSaved.last, startsWith('-'));

    final taskSaved = <String>[];
    final task = controller(taskSaved);
    addTearDown(task.dispose);
    task.applyMagic(
      const MagicRequest(
        action: MagicAction.task,
        id: 'task-1',
        value: 'Write report',
      ),
    );
    expect(taskSaved.last, contains('#tylog.task('));
    expect(taskSaved.last, contains('text: "Write report"'));
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

  test('heading formats only the current physical line and exits on Enter', () {
    final saved = <String>[];
    final controller = TyLogEditingController(
      source: 'first\nsecond\nthird',
      onSourceChanged: saved.add,
      onError: (error) => fail('$error'),
      onProtectedTap: (_) {},
    );
    addTearDown(controller.dispose);
    controller.selection = const TextSelection.collapsed(offset: 8);

    controller.setHeading();

    expect(controller.text, 'first\n\nsecond\n\nthird');
    expect(saved.last, 'first\n\n= second\n\nthird');
    expect(controller.selection.baseOffset, 9);

    controller.selection = const TextSelection.collapsed(offset: 13);
    controller.value = const TextEditingValue(
      text: 'first\n\nsecond\n\n\nthird',
      selection: TextSelection.collapsed(offset: 14),
    );
    expect(controller.text, 'first\n\nsecond\n\n\n\nthird');
    expect(controller.document.blocks[2].style, TyLogBlockStyle.paragraph);
  });

  test('a bare email parses as a mailto link atom and round-trips', () {
    final document = TyLogDocument.parse('Email: andre.berloga@gmail.com now');
    final atoms = document.blocks
        .expand((block) => block.parts)
        .where((part) => part.isAtom)
        .toList();
    expect(atoms.length, 1);
    expect(atoms.single.source, '#link("mailto:andre.berloga@gmail.com")[andre.berloga\\@gmail.com]');
    expect(atoms.single.label, 'andre.berloga@gmail.com');
    // Untouched, the bare source is preserved verbatim (no bulk rewrite)...
    expect(document.toSource(), 'Email: andre.berloga@gmail.com now');
    expect(
      TyLogDocument.parse(document.toSource()).visibleText,
      document.visibleText,
    );
  });

  test('editing an email note migrates the bare address to #link on save', () {
    final saved = <String>[];
    final controller = TyLogEditingController(
      source: 'Reach me: a@b.com',
      onSourceChanged: saved.add,
      onError: (error) => fail('$error'),
      onProtectedTap: (_) {},
    );
    addTearDown(controller.dispose);
    // Append a character to the paragraph so the block becomes dirty.
    controller.value = TextEditingValue(
      text: '${controller.text}!',
      selection: TextSelection.collapsed(offset: controller.text.length + 1),
    );
    expect(saved.last, contains('#link("mailto:a@b.com")[a\\@b.com]'));
  });

  test('a citation @key stays a citation; an email @domain does not', () {
    final document = TyLogDocument.parse('write user@host.com see @knuth1984');
    final sources = document.blocks
        .expand((block) => block.parts)
        .where((part) => part.isAtom)
        .map((part) => part.source)
        .toList();
    expect(sources, [
      '#link("mailto:user@host.com")[user\\@host.com]',
      '@knuth1984',
    ]);
  });

  test('typing an email then space converts it to a mailto link chip', () {
    final saved = <String>[];
    final controller = TyLogEditingController(
      source: 'Contact ',
      onSourceChanged: saved.add,
      onError: (error) => fail('$error'),
      onProtectedTap: (_) {},
    );
    addTearDown(controller.dispose);
    controller.selection = const TextSelection.collapsed(offset: 8);
    for (final ch in 'me@x.com '.split('')) {
      final at = controller.selection.baseOffset;
      controller.value = TextEditingValue(
        text: controller.text.replaceRange(at, at, ch),
        selection: TextSelection.collapsed(offset: at + 1),
      );
    }
    expect(saved.last, 'Contact #link("mailto:me@x.com")[me\\@x.com] ');
    expect(
      controller.document.blocks
          .expand((block) => block.parts)
          .where((part) => part.isAtom)
          .length,
      1,
    );
  });

  test('a paragraph line starting with a list marker round-trips (paste)', () {
    // Pasting "- item" lands as a paragraph; without escaping it re-parses as a
    // list, fails toSource validation, and the edit reverts.
    final saved = <String>[];
    final controller = TyLogEditingController(
      source: 'note',
      onSourceChanged: saved.add,
      onError: (error) => fail('$error'),
      onProtectedTap: (_) {},
    );
    addTearDown(controller.dispose);
    const pasted = '\n\n- one\n- two';
    controller.value = TextEditingValue(
      text: 'note$pasted',
      selection: TextSelection.collapsed(offset: 'note$pasted'.length),
    );
    expect(controller.text, 'note\n\n- one\n- two');
    // A trailing newline (Enter) still applies rather than being reverted.
    controller.value = TextEditingValue(
      text: '${controller.text}\n',
      selection: TextSelection.collapsed(offset: controller.text.length + 1),
    );
    expect(controller.text, 'note\n\n- one\n- two\n');
    expect(saved.last, contains('\\- one'));
  });

  test('Enter in the middle of a numbered list renumbers, not reverts', () {
    final saved = <String>[];
    final controller = TyLogEditingController(
      source: '+ a\n+ b',
      onSourceChanged: saved.add,
      onError: (error) => fail('$error'),
      onProtectedTap: (_) {},
    );
    addTearDown(controller.dispose);
    expect(controller.text, '1. a\n2. b');
    final at = controller.text.indexOf('1. a') + '1. a'.length;
    controller.selection = TextSelection.collapsed(offset: at);
    controller.value = TextEditingValue(
      text: controller.text.replaceRange(at, at, '\n'),
      selection: TextSelection.collapsed(offset: at + 1),
    );
    expect(controller.text, '1. a\n2. \n3. b');
    expect(saved.last, '+ a\n+ \n+ b');
  });

  testWidgets('an #image atom renders as a real picture when bytes resolve', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TyLogReadView(
            source: 'See #image("/assets/x.png") end',
            imageResolver: (path) async =>
                path == '/assets/x.png' ? _tinyPng : null,
          ),
        ),
      ),
    );
    await tester.pump(); // resolve the bytes future
    await tester.pump();
    expect(find.byType(Image), findsOneWidget);
    expect(find.textContaining('/assets/x.png'), findsNothing);
  });

  testWidgets('an #image atom falls back to a chip when bytes are missing', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TyLogReadView(
            source: 'See #image("/assets/x.png") end',
            imageResolver: (path) async => null,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.byType(Image), findsNothing);
    expect(find.textContaining('/assets/x.png'), findsOneWidget);
  });

  testWidgets('inline chips show a type-specific icon', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TyLogReadView(
            source:
                'a #link("mailto:me@x.com")[me\\@x.com] '
                'b #link("https://x.com")[site] '
                'c #tylog.ref-note("p")[Ann] '
                'd #tylog.ref-note("q")[Rome] '
                'e #tylog.tag("topic")',
            resolveKind: (id) => const {'p': 'person', 'q': 'place'}[id],
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byIcon(Icons.alternate_email), findsOneWidget); // email
    expect(find.byIcon(Icons.link), findsOneWidget); // http link
    expect(find.byIcon(Icons.person_outline), findsOneWidget); // person
    expect(find.byIcon(Icons.location_on_outlined), findsOneWidget); // place
    expect(find.byIcon(Icons.tag), findsOneWidget); // tag
  });

  test('list toggles one line, continues, and empty Enter exits', () {
    final saved = <String>[];
    final controller = TyLogEditingController(
      source: 'item',
      onSourceChanged: saved.add,
      onError: (error) => fail('$error'),
      onProtectedTap: (_) {},
    );
    addTearDown(controller.dispose);
    controller.selection = const TextSelection.collapsed(offset: 4);

    controller.setBulletList();
    expect(controller.text, '• item');
    expect(controller.selection.baseOffset, 6);

    controller.value = const TextEditingValue(
      text: '• item\n',
      selection: TextSelection.collapsed(offset: 7),
    );
    expect(controller.text, '• item\n• ');
    expect(controller.selection.baseOffset, 9);

    controller.value = const TextEditingValue(
      text: '• item\n• \n',
      selection: TextSelection.collapsed(offset: 10),
    );
    expect(controller.text, '• item\n\n');
    expect(saved.last, '- item\n\n');

    controller.selection = const TextSelection.collapsed(offset: 2);
    controller.setBulletList();
    expect(controller.text, 'item\n\n');
    expect(saved.last, 'item\n\n');
  });

  test('programmatic actions finish composition and accept more IME text', () {
    final saved = <String>[];
    final controller = TyLogEditingController(
      source: 'a',
      onSourceChanged: saved.add,
      onError: (error) => fail('$error'),
      onProtectedTap: (_) {},
    );
    addTearDown(controller.dispose);
    controller.value = const TextEditingValue(
      text: 'ab',
      selection: TextSelection.collapsed(offset: 2),
      composing: TextRange(start: 1, end: 2),
    );

    controller.setHeading();
    expect(controller.value.composing, TextRange.empty);
    expect(saved.last, '= ab');

    controller.value = const TextEditingValue(
      text: 'abc',
      selection: TextSelection.collapsed(offset: 3),
      composing: TextRange(start: 2, end: 3),
    );
    controller.value = controller.value.copyWith(composing: TextRange.empty);
    expect(saved.last, '= abc');
  });

  test('task magic places the caret at the end of the task text', () {
    final saved = <String>[];
    final controller = TyLogEditingController(
      source: 'seed\n',
      onSourceChanged: saved.add,
      onError: (error) => fail('$error'),
      onProtectedTap: (_) {},
    );
    addTearDown(controller.dispose);
    controller.selection = TextSelection.collapsed(
      offset: controller.text.length,
    );

    controller.applyMagic(
      const MagicRequest(
        action: MagicAction.task,
        id: 'task-1',
        value: 'Write report',
      ),
    );
    final caret =
        controller.text.indexOf('Write report') + 'Write report'.length;
    // The task renders as an editable checklist line now, so the caret sits
    // right after its text — not at the very end of the document (there is
    // still a trailing empty paragraph after it).
    expect(controller.selection.baseOffset, caret);
    expect(controller.text, contains('☐ Write report'));
    controller.value = TextEditingValue(
      text: controller.text.replaceRange(caret, caret, 'x'),
      selection: TextSelection.collapsed(offset: caret + 1),
      composing: TextRange(start: caret, end: caret + 1),
    );
    controller.value = controller.value.copyWith(composing: TextRange.empty);

    expect(saved.last, startsWith('seed\n\n#tylog.task('));
    expect(saved.last, contains('text: "Write reportx"'));
  });

  // These four tests exercise the generic protected-chip boundary machinery
  // in insertNewline/_handleValue. They used to insert a task to get a chip
  // to poke at; tasks now render as editable checklist lines instead, so a
  // table (still a protected block) stands in as the chip.
  test('Enter at a protected block trailing boundary opens a paragraph', () {
    final saved = <String>[];
    final controller = TyLogEditingController(
      source: 'seed\n',
      onSourceChanged: saved.add,
      onError: (error) => fail('$error'),
      onProtectedTap: (_) {},
    );
    addTearDown(controller.dispose);
    controller.selection = TextSelection.collapsed(
      offset: controller.text.length,
    );
    controller.applyMagic(const MagicRequest(action: MagicAction.table));

    // Mobile places the caret here: just after the chip, before the gap.
    final boundary = controller.text.indexOf('￼') + 1;
    controller.selection = TextSelection.collapsed(offset: boundary);
    controller.value = TextEditingValue(
      text: controller.text.replaceRange(boundary, boundary, '\n'),
      selection: TextSelection.collapsed(offset: boundary + 1),
    );

    expect(controller.selection.baseOffset, boundary + 2);
    final caret = controller.selection.baseOffset;
    controller.value = TextEditingValue(
      text: controller.text.replaceRange(caret, caret, 'x'),
      selection: TextSelection.collapsed(offset: caret + 1),
    );
    expect(controller.text, contains('￼\n\nx'));
    expect(saved.last, contains('#table('));
  });

  test('typing at a protected block trailing boundary starts a paragraph', () {
    final saved = <String>[];
    final controller = TyLogEditingController(
      source: 'seed\n',
      onSourceChanged: saved.add,
      onError: (error) => fail('$error'),
      onProtectedTap: (_) {},
    );
    addTearDown(controller.dispose);
    controller.selection = TextSelection.collapsed(
      offset: controller.text.length,
    );
    controller.applyMagic(const MagicRequest(action: MagicAction.table));

    final boundary = controller.text.indexOf('￼') + 1;
    controller.selection = TextSelection.collapsed(offset: boundary);
    controller.value = TextEditingValue(
      text: controller.text.replaceRange(boundary, boundary, 'x'),
      selection: TextSelection.collapsed(offset: boundary + 1),
    );

    expect(controller.text, contains('￼\n\nx'));
    expect(controller.selection.baseOffset, boundary + 3);
    expect(saved.last, contains('#table('));
  });

  test('typing at a protected block leading boundary lands above it', () {
    final saved = <String>[];
    final controller = TyLogEditingController(
      source: 'seed\n',
      onSourceChanged: saved.add,
      onError: (error) => fail('$error'),
      onProtectedTap: (_) {},
    );
    addTearDown(controller.dispose);
    controller.selection = TextSelection.collapsed(
      offset: controller.text.length,
    );
    controller.applyMagic(const MagicRequest(action: MagicAction.table));

    // Tapping the chip line places the caret just before the chip.
    final leading = controller.text.indexOf('￼');
    controller.selection = TextSelection.collapsed(offset: leading);
    controller.value = TextEditingValue(
      text: controller.text.replaceRange(leading, leading, 'x'),
      selection: TextSelection.collapsed(offset: leading + 1),
    );

    expect(controller.text, contains('x\n\n￼'));
    expect(controller.selection.baseOffset, leading + 1);
    expect(saved.last, contains('#table('));
  });

  test('Enter at a protected block leading boundary opens a line above', () {
    final saved = <String>[];
    final controller = TyLogEditingController(
      source: 'seed\n',
      onSourceChanged: saved.add,
      onError: (error) => fail('$error'),
      onProtectedTap: (_) {},
    );
    addTearDown(controller.dispose);
    controller.selection = TextSelection.collapsed(
      offset: controller.text.length,
    );
    controller.applyMagic(const MagicRequest(action: MagicAction.table));

    final leading = controller.text.indexOf('￼');
    controller.selection = TextSelection.collapsed(offset: leading);
    controller.value = TextEditingValue(
      text: controller.text.replaceRange(leading, leading, '\n'),
      selection: TextSelection.collapsed(offset: leading + 1),
    );

    // Caret stays with the chip, a writable blank line sits above it.
    expect(controller.text, contains('\n\n￼'));
    expect(controller.selection.baseOffset, leading + 2);
    expect(saved.last, contains('#table('));
  });

  test('typing after loadSource ending in a protected block appends a paragraph', () {
    final saved = <String>[];
    final controller = TyLogEditingController(
      source: 'seed\n',
      onSourceChanged: saved.add,
      onError: (error) => fail('$error'),
      onProtectedTap: (_) {},
    );
    addTearDown(controller.dispose);
    controller.selection = TextSelection.collapsed(
      offset: controller.text.length,
    );
    controller.applyMagic(const MagicRequest(action: MagicAction.table));

    // Reload a note whose source ends with the table: the trailing empty
    // paragraph is dropped on reparse and the caret lands on the chip's end.
    controller.loadSource(saved.last.trimRight());
    expect(controller.text, endsWith('￼'));
    expect(controller.selection.baseOffset, controller.text.length);

    final caret = controller.selection.baseOffset;
    controller.value = TextEditingValue(
      text: '${controller.text}x',
      selection: TextSelection.collapsed(offset: caret + 1),
    );

    expect(controller.text, endsWith('￼\n\nx'));
    expect(saved.last, contains('#table('));
    expect(saved.last, endsWith('\n\nx'));
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
          body: TyLogRichEditor(controller: controller, onInsert: () async {}),
        ),
      ),
    );

    // The delimited custom call renders as an inline atom labelled by its
    // bracket content; tapping it still opens the protected editor.
    expect(find.text('Keep exactly'), findsOneWidget);
    await tester.tap(find.text('Keep exactly'));
    expect(opened, isNotNull);
  });

  testWidgets('unknown inline call keeps surrounding prose editable', (
    tester,
  ) async {
    const source = 'Before #footnote[note text] after and #link("https://x")\n';
    final controller = TyLogEditingController(
      source: source,
      onSourceChanged: (_) {},
      onError: (error) => fail('$error'),
      onProtectedTap: (_) {},
    );
    addTearDown(controller.dispose);

    expect(controller.text, contains('Before ￼ after and ￼'));
    expect(controller.document.toSource(), source);

    // Prose around the atoms stays editable.
    final after = controller.text.indexOf('after');
    controller.document.replace(after, after + 5, 'AFTER');
    expect(controller.document.toSource(), contains('AFTER and'));
    expect(controller.document.toSource(), contains('#footnote[note text]'));
    expect(controller.document.toSource(), contains('#link("https://x")'));
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
          body: TyLogRichEditor(controller: controller, onInsert: () async {}),
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

  testWidgets('insert callback restores editor focus when it completes', (
    tester,
  ) async {
    final controller = TyLogEditingController(
      source: 'text',
      onSourceChanged: (_) {},
      onError: (error) => fail('$error'),
      onProtectedTap: (_) {},
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TyLogRichEditor(
            controller: controller,
            onInsert: () async {
              FocusManager.instance.primaryFocus?.unfocus();
              await Future<void>.delayed(Duration.zero);
            },
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('rich-journal-editor')));
    await tester.pump();
    await tester.tap(find.byTooltip('Insert'));
    await tester.pumpAndSettle();

    expect(
      tester.widget<EditableText>(find.byType(EditableText)).focusNode.hasFocus,
      isTrue,
    );
  });

  test(
    'a full-fat task renders as an editable checklist line, byte-identical',
    () {
      const todoSource =
          '#tylog.task(\n'
          '  id: "t1",\n'
          '  text: "Ship it",\n'
          '  due: "2026-07-20",\n'
          '  project: "Launch",\n'
          '  priority: "high",\n'
          '  recurrence: "weekly",\n'
          '  properties: (owner: "alex"),\n'
          ')';
      final controller = TyLogEditingController(
        source: todoSource,
        onSourceChanged: (_) {},
        onError: (error) => fail('$error'),
        onProtectedTap: (_) {},
      );
      addTearDown(controller.dispose);

      expect(controller.text, '☐ Ship it');
      expect(controller.text, isNot(contains('￼')));
      expect(TyLogDocument.parse(todoSource).toSource(), todoSource);

      const doneSource =
          '#tylog.task(\n'
          '  id: "t1",\n'
          '  text: "Ship it",\n'
          '  status: "done",\n'
          '  due: "2026-07-20",\n'
          '  project: "Launch",\n'
          '  priority: "high",\n'
          '  recurrence: "weekly",\n'
          '  properties: (owner: "alex"),\n'
          ')';
      expect(TyLogDocument.parse(doneSource).visibleText, '☑ Ship it');
    },
  );

  test('typing at the end of a task line changes only the text field', () {
    const source =
        '#tylog.task(\n'
        '  id: "t1",\n'
        '  text: "Ship it",\n'
        '  due: "2026-07-20",\n'
        '  project: "Launch",\n'
        ')';
    String? saved;
    final controller = TyLogEditingController(
      source: source,
      onSourceChanged: (value) => saved = value,
      onError: (error) => fail('$error'),
      onProtectedTap: (_) {},
    );
    addTearDown(controller.dispose);

    controller.value = TextEditingValue(
      text: '${controller.text} today',
      selection: TextSelection.collapsed(offset: controller.text.length + 6),
    );

    expect(
      saved,
      source.replaceFirst('text: "Ship it"', 'text: "Ship it today"'),
    );
  });

  test('Enter at the end of a task line opens a paragraph beneath it', () {
    const source =
        '#tylog.task(id: "t1", text: "Ship it", due: none, project: none)';
    final saved = <String>[];
    final controller = TyLogEditingController(
      source: source,
      onSourceChanged: saved.add,
      onError: (error) => fail('$error'),
      onProtectedTap: (_) {},
    );
    addTearDown(controller.dispose);

    controller.selection = TextSelection.collapsed(
      offset: controller.text.length,
    );
    controller.value = TextEditingValue(
      text: '${controller.text}\n',
      selection: TextSelection.collapsed(offset: controller.text.length + 1),
    );

    expect(controller.text, '☐ Ship it\n\n');
    expect(controller.selection.baseOffset, controller.text.length);
    expect(saved.last, contains('#tylog.task('));

    controller.value = TextEditingValue(
      text: '${controller.text}note',
      selection: TextSelection.collapsed(offset: controller.text.length + 4),
    );
    expect(controller.text, '☐ Ship it\n\nnote');
    expect(saved.last, contains('#tylog.task('));
    expect(saved.last, endsWith('\n\nnote'));
  });

  test('backspace at task content start converts the line to a paragraph', () {
    const source =
        '#tylog.task(id: "t1", text: "Ship it", due: none, project: none)';
    final saved = <String>[];
    final controller = TyLogEditingController(
      source: source,
      onSourceChanged: saved.add,
      onError: (error) => fail('$error'),
      onProtectedTap: (_) {},
    );
    addTearDown(controller.dispose);

    // Caret right after "☐ "; backspace removes the char at lineStart + 1
    // (the space), which is exactly what a real backspace there produces.
    controller.selection = const TextSelection.collapsed(offset: 2);
    controller.value = TextEditingValue(
      text: controller.text.replaceRange(1, 2, ''),
      selection: const TextSelection.collapsed(offset: 1),
    );

    expect(controller.text, 'Ship it');
    expect(saved.last, isNot(contains('#tylog.task')));
  });

  test('Enter on an empty task line converts it to a paragraph', () {
    final saved = <String>[];
    final controller = TyLogEditingController(
      source: '',
      onSourceChanged: saved.add,
      onError: (error) => fail('$error'),
      onProtectedTap: (_) {},
    );
    addTearDown(controller.dispose);
    controller.applyMagic(
      const MagicRequest(action: MagicAction.task, id: 'task-1', value: ''),
    );
    // insertBlock always leaves a trailing empty paragraph after the task.
    expect(controller.text, '☐ \n\n');
    expect(controller.selection.baseOffset, 2);

    controller.value = TextEditingValue(
      text: controller.text.replaceRange(2, 2, '\n'),
      selection: const TextSelection.collapsed(offset: 3),
    );

    expect(saved.last, isNot(contains('#tylog.task')));
  });

  test('tapping the checkbox toggles status and preserves other fields', () {
    const source =
        '#tylog.task(\n'
        '  id: "t1",\n'
        '  text: "Ship it",\n'
        '  due: "2026-07-20",\n'
        '  project: "Launch",\n'
        ')';
    final saved = <String>[];
    final controller = TyLogEditingController(
      source: source,
      onSourceChanged: saved.add,
      onError: (error) => fail('$error'),
      onProtectedTap: (_) {},
    );
    addTearDown(controller.dispose);

    controller.selection = const TextSelection.collapsed(offset: 0);
    controller.handleEditorTap();

    expect(controller.text, startsWith('☑'));
    expect(controller.selection.baseOffset, 2);
    expect(saved.last, contains('status: "done"'));
    expect(saved.last, contains('text: "Ship it"'));
    expect(saved.last, contains('due: "2026-07-20"'));
    expect(saved.last, contains('project: "Launch"'));

    controller.selection = const TextSelection.collapsed(offset: 0);
    controller.handleEditorTap();
    expect(controller.text, startsWith('☐'));
    expect(saved.last, contains('status: "todo"'));

    // Stale-source case: edit the text first, then toggle. Both the new
    // text and the new status must land in the saved source.
    controller.selection = TextSelection.collapsed(
      offset: controller.text.length,
    );
    controller.value = TextEditingValue(
      text: '${controller.text} today',
      selection: TextSelection.collapsed(offset: controller.text.length + 6),
    );
    expect(saved.last, contains('text: "Ship it today"'));
    // Status was explicitly written back to "todo" by the previous toggle;
    // a plain text edit must leave it untouched.
    expect(saved.last, contains('status: "todo"'));

    controller.selection = const TextSelection.collapsed(offset: 0);
    controller.handleEditorTap();
    expect(saved.last, contains('text: "Ship it today"'));
    expect(saved.last, contains('status: "done"'));
  });

  test('typing between the glyph and space is rejected', () {
    const source =
        '#tylog.task(id: "t1", text: "Ship it", due: none, project: none)';
    final errors = <Object>[];
    final controller = TyLogEditingController(
      source: source,
      onSourceChanged: (_) {},
      onError: errors.add,
      onProtectedTap: (_) {},
    );
    addTearDown(controller.dispose);
    final before = controller.text;

    controller.value = TextEditingValue(
      text: controller.text.replaceRange(1, 1, 'x'),
      selection: const TextSelection.collapsed(offset: 2),
    );

    expect(errors, isNotEmpty);
    expect(controller.text, before);
  });

  test('editing one task leaves a sibling task byte-identical', () {
    const source =
        'Intro\n\n'
        '#tylog.task(id: "t1", text: "First", due: none, project: none)\n\n'
        'Middle\n\n'
        '#tylog.task(id: "t2", text: "Second", due: none, project: none)\n';
    final saved = <String>[];
    final controller = TyLogEditingController(
      source: source,
      onSourceChanged: saved.add,
      onError: (error) => fail('$error'),
      onProtectedTap: (_) {},
    );
    addTearDown(controller.dispose);

    final target = controller.text.lastIndexOf('Second') + 'Second'.length;
    controller.selection = TextSelection.collapsed(offset: target);
    controller.value = TextEditingValue(
      text: controller.text.replaceRange(target, target, '!'),
      selection: TextSelection.collapsed(offset: target + 1),
    );

    expect(saved.last, contains('#tylog.task(id: "t1", text: "First"'));
    expect(saved.last, contains('text: "Second!"'));
  });

  test(
    'quotes and backslashes in task text round-trip through save and load',
    () {
      const source =
          '#tylog.task(id: "t1", text: "Plain", due: none, project: none)';
      String? saved;
      final controller = TyLogEditingController(
        source: source,
        onSourceChanged: (value) => saved = value,
        onError: (error) => fail('$error'),
        onProtectedTap: (_) {},
      );
      addTearDown(controller.dispose);

      const newText = 'Say "hi" \\ ok';
      controller.value = TextEditingValue(
        text: '☐ $newText',
        selection: TextSelection.collapsed(offset: 2 + newText.length),
      );

      expect(saved, isNotNull);
      final reloaded = TyLogEditingController(
        source: saved!,
        onSourceChanged: (_) {},
        onError: (error) => fail('$error'),
        onProtectedTap: (_) {},
      );
      addTearDown(reloaded.dispose);
      expect(reloaded.text, '☐ $newText');
    },
  );

  test('applyMagic(task) places the caret at the end of the task text', () {
    final saved = <String>[];
    final controller = TyLogEditingController(
      source: '',
      onSourceChanged: saved.add,
      onError: (error) => fail('$error'),
      onProtectedTap: (_) {},
    );
    addTearDown(controller.dispose);

    controller.applyMagic(
      const MagicRequest(
        action: MagicAction.task,
        id: 'task-1',
        value: 'Write report',
      ),
    );

    expect(controller.text, contains('☐ Write report'));
    final caret =
        controller.text.indexOf('Write report') + 'Write report'.length;
    expect(controller.selection.baseOffset, caret);

    controller.value = TextEditingValue(
      text: controller.text.replaceRange(caret, caret, '!'),
      selection: TextSelection.collapsed(offset: caret + 1),
    );
    expect(controller.text, contains('Write report!'));
    expect(saved.last, contains('#tylog.task('));
  });

  test('a structurally malformed task stays a protected chip', () {
    const source = '#tylog.task(id: someVar, text: myText)';
    final controller = TyLogEditingController(
      source: source,
      onSourceChanged: (_) {},
      onError: (error) => fail('$error'),
      onProtectedTap: (_) {},
    );
    addTearDown(controller.dispose);

    expect(controller.text, '￼');
    expect(TyLogDocument.parse(source).toSource(), source);
  });

  const fullFatTaskAndNote =
      '#tylog.task(\n'
      '  id: "t1",\n'
      '  text: "Ship it",\n'
      '  due: "2026-07-20",\n'
      '  project: "Launch",\n'
      '  priority: "high",\n'
      '  recurrence: "weekly",\n'
      '  properties: (owner: "alex"),\n'
      ')\n\n'
      'Notes here';

  test(
    'pasting text with a blank line into a task line is refused and the '
    'task is preserved',
    () {
      final errors = <Object>[];
      final controller = TyLogEditingController(
        source: fullFatTaskAndNote,
        onSourceChanged: (_) {},
        onError: errors.add,
        onProtectedTap: (_) {},
      );
      addTearDown(controller.dispose);

      final before = controller.text;
      expect(before, '☐ Ship it\n\nNotes here');
      final caret = before.indexOf('Ship');

      controller.selection = TextSelection.collapsed(offset: caret);
      controller.value = TextEditingValue(
        text: before.replaceRange(caret, caret, 'X\n\nY'),
        selection: TextSelection.collapsed(offset: caret + 4),
      );

      expect(errors, isNotEmpty);
      expect(controller.text, before);
      // Task bytes, including recurrence/properties, survive intact.
      expect(controller.document.toSource(), fullFatTaskAndNote);
    },
  );

  test(
    'a selection spanning from mid-task-text into the next paragraph is '
    'refused',
    () {
      final errors = <Object>[];
      final controller = TyLogEditingController(
        source: fullFatTaskAndNote,
        onSourceChanged: (_) {},
        onError: errors.add,
        onProtectedTap: (_) {},
      );
      addTearDown(controller.dispose);

      final before = controller.text;
      final start = before.indexOf('Ship');
      final end = before.indexOf('Notes') + 2;

      controller.selection = TextSelection(baseOffset: start, extentOffset: end);
      controller.value = TextEditingValue(
        text: before.replaceRange(start, end, 'Z'),
        selection: TextSelection.collapsed(offset: start + 1),
      );

      expect(errors, isNotEmpty);
      expect(controller.text, before);
      expect(controller.document.toSource(), fullFatTaskAndNote);
    },
  );

  test(
    'pasting a blank-line paste at the exact end of a task line is refused '
    'and the task is preserved',
    () {
      final errors = <Object>[];
      final saved = <String>[];
      final controller = TyLogEditingController(
        source: fullFatTaskAndNote,
        onSourceChanged: saved.add,
        onError: errors.add,
        onProtectedTap: (_) {},
      );
      addTearDown(controller.dispose);

      final before = controller.text;
      // Caret exactly at the task line's trailing boundary (range.end),
      // the ordinary end-of-task caret position.
      final caret = before.indexOf('\n\n');
      expect(before.substring(0, caret), '☐ Ship it');

      controller.selection = TextSelection.collapsed(offset: caret);
      controller.value = TextEditingValue(
        text: before.replaceRange(caret, caret, 'Foo\n\nBar'),
        selection: TextSelection.collapsed(offset: caret + 8),
      );

      expect(errors, isNotEmpty);
      expect(controller.text, before);
      expect(controller.document.toSource(), fullFatTaskAndNote);
      if (saved.isNotEmpty) {
        expect(saved.last, contains('recurrence: "weekly"'));
        expect(saved.last, contains('properties: (owner: "alex")'));
        expect(saved.last, contains('#tylog.task('));
      }
    },
  );

  test(
    'deleting a whole task line (through into the next paragraph) is '
    'allowed and drops the task from the source',
    () {
      final saved = <String>[];
      final controller = TyLogEditingController(
        source: fullFatTaskAndNote,
        onSourceChanged: saved.add,
        onError: (error) => fail('$error'),
        onProtectedTap: (_) {},
      );
      addTearDown(controller.dispose);

      final before = controller.text;
      // Covers the entire task line's range plus the first char of the
      // following paragraph ("N" of "Notes").
      const start = 0;
      final end = before.indexOf('Notes') + 1;

      controller.selection = TextSelection(baseOffset: start, extentOffset: end);
      controller.value = TextEditingValue(
        text: before.replaceRange(start, end, ''),
        selection: const TextSelection.collapsed(offset: start),
      );

      expect(saved, isNotEmpty);
      expect(saved.last, isNot(contains('#tylog.task(')));
    },
  );

  testWidgets('tapping the task checkbox glyph toggles its status', (
    tester,
  ) async {
    const source =
        '#tylog.task(id: "t1", text: "Ship it", due: none, project: none)\n';
    String? saved;
    final controller = TyLogEditingController(
      source: source,
      onSourceChanged: (value) => saved = value,
      onError: (error) => fail('$error'),
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
    await tester.tap(find.byKey(const Key('rich-journal-editor')));
    await tester.pump();

    final editableState = tester.state<EditableTextState>(
      find.byType(EditableText),
    );
    final renderEditable = editableState.renderEditable;
    final caretRect = renderEditable.getLocalRectForCaret(
      const TextPosition(offset: 0),
    );
    await tester.tapAt(renderEditable.localToGlobal(caretRect.center));
    await tester.pump();

    expect(saved, contains('status: "done"'));
  });

  testWidgets(
    'typing @Fer and tapping a suggestion inserts a byte-identical mention',
    (tester) async {
      String? saved;
      final controller = TyLogEditingController(
        source: '',
        onSourceChanged: (value) => saved = value,
        onError: (error) => fail('$error'),
        onProtectedTap: (_) {},
      );
      addTearDown(controller.dispose);
      final queries = <String>[];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TyLogRichEditor(
              controller: controller,
              onInsert: () async {},
              onMentionQuery: (query, kind) async {
                queries.add(query);
                return const [
                  MentionSuggestion(
                    id: 'FernandoMarson',
                    title: 'FernandoMarson',
                  ),
                ];
              },
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('rich-journal-editor')));
      await tester.pump();
      await tester.enterText(
        find.byKey(const Key('rich-journal-editor')),
        '@Fer',
      );
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump();

      expect(queries, contains('Fer'));
      expect(
        find.byKey(const Key('autocomplete-mention-FernandoMarson')),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const Key('autocomplete-mention-FernandoMarson')),
      );
      await tester.pumpAndSettle();

      final expectedSnippet = applyMagicEdit(
        '@Fer',
        const TextSelection(baseOffset: 0, extentOffset: 4),
        const MagicRequest(
          action: MagicAction.mention,
          id: 'FernandoMarson',
          value: 'FernandoMarson',
        ),
      ).text;
      expect(expectedSnippet, contains('#tylog.ref-note("FernandoMarson")'));
      expect(saved, contains(expectedSnippet));
      expect(
        find.byKey(const Key('autocomplete-mention-list')),
        findsNothing,
      );
    },
  );

  testWidgets(
    'typing [[ completes a note into a plain ref-note (no @ prefix)',
    (tester) async {
      String? saved;
      final controller = TyLogEditingController(
        source: '',
        onSourceChanged: (value) => saved = value,
        onError: (error) => fail('$error'),
        onProtectedTap: (_) {},
      );
      addTearDown(controller.dispose);
      AutocompleteTriggerKind? seenKind;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TyLogRichEditor(
              controller: controller,
              onInsert: () async {},
              onMentionQuery: (query, kind) async {
                seenKind = kind;
                return const [
                  MentionSuggestion(id: 'esp32-panel', title: 'ESP32 panel'),
                  MentionSuggestion(
                    id: 'esp32',
                    title: 'esp32',
                    kind: MentionKind.concept,
                  ),
                ];
              },
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('rich-journal-editor')));
      await tester.pump();
      await tester.enterText(
        find.byKey(const Key('rich-journal-editor')),
        '[[ESP',
      );
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump();

      expect(seenKind, AutocompleteTriggerKind.wikiLink);
      await tester.tap(
        find.byKey(const Key('autocomplete-mention-esp32-panel')),
      );
      await tester.pumpAndSettle();

      // Plain note reference — no leftover "[[" and no "@" prefix.
      expect(saved, contains('#tylog.ref-note("esp32-panel")[ESP32 panel]'));
      expect(saved, isNot(contains('[[')));
      expect(saved, isNot(contains('@')));
    },
  );

  testWidgets('typing [[ completes an existing tag into #tylog.tag', (
    tester,
  ) async {
    String? saved;
    final controller = TyLogEditingController(
      source: '',
      onSourceChanged: (value) => saved = value,
      onError: (error) => fail('$error'),
      onProtectedTap: (_) {},
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TyLogRichEditor(
            controller: controller,
            onInsert: () async {},
            onMentionQuery: (query, kind) async => const [
              MentionSuggestion(
                id: 'esp32',
                title: 'esp32',
                kind: MentionKind.concept,
              ),
            ],
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('rich-journal-editor')));
    await tester.pump();
    await tester.enterText(
      find.byKey(const Key('rich-journal-editor')),
      '[[esp',
    );
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump();

    await tester.tap(find.byKey(const Key('autocomplete-mention-esp32')));
    await tester.pumpAndSettle();

    expect(saved, contains('#tylog.tag("esp32")'));
    expect(saved, isNot(contains('[[')));
  });

  test('collapsed strike/underline/mono style subsequently typed text', () {
    void checkPrefix(void Function(TyLogEditingController) toggle, String open) {
      String? saved;
      final controller = TyLogEditingController(
        source: _source,
        onSourceChanged: (value) => saved = value,
        onError: (error) => fail('$error'),
        onProtectedTap: (_) {},
      );
      addTearDown(controller.dispose);
      controller.selection = const TextSelection.collapsed(offset: 0);

      toggle(controller);
      controller.value = controller.value.copyWith(
        text: 'Да ${controller.text}',
        selection: const TextSelection.collapsed(offset: 3),
      );

      expect(saved, contains('$open' 'Да '));
    }

    checkPrefix((c) => c.toggleStrike(), '#strike[');
    checkPrefix((c) => c.toggleUnderline(), '#underline[');
    checkPrefix((c) => c.toggleMono(), '`');
  });

  test('range toggle emits strike, underline, and mono wrappers', () {
    TyLogEditingController controller(List<String> saved) =>
        TyLogEditingController(
          source: _source,
          onSourceChanged: saved.add,
          onError: (error) => fail('$error'),
          onProtectedTap: (_) {},
        );
    const word = 'привет';

    final strikeSaved = <String>[];
    final strikeController = controller(strikeSaved);
    addTearDown(strikeController.dispose);
    strikeController.selection = const TextSelection(
      baseOffset: 0,
      extentOffset: word.length,
    );
    strikeController.toggleStrike();
    expect(strikeSaved.last, contains('#strike[привет]'));

    final underlineSaved = <String>[];
    final underlineController = controller(underlineSaved);
    addTearDown(underlineController.dispose);
    underlineController.selection = const TextSelection(
      baseOffset: 0,
      extentOffset: word.length,
    );
    underlineController.toggleUnderline();
    expect(underlineSaved.last, contains('#underline[привет]'));

    final monoSaved = <String>[];
    final monoController = controller(monoSaved);
    addTearDown(monoController.dispose);
    monoController.selection = const TextSelection(
      baseOffset: 0,
      extentOffset: word.length,
    );
    monoController.toggleMono();
    expect(monoSaved.last, contains('`привет`'));
  });

  test(
    'highlight toggle applies default fill, palette sets an explicit fill, '
    'and an unknown fill round-trips verbatim',
    () {
      String? saved;
      final controller = TyLogEditingController(
        source: _source,
        onSourceChanged: (value) => saved = value,
        onError: (error) => fail('$error'),
        onProtectedTap: (_) {},
      );
      addTearDown(controller.dispose);
      const word = 'привет';
      controller.selection = const TextSelection(
        baseOffset: 0,
        extentOffset: word.length,
      );

      controller.toggleHighlight();
      expect(saved, contains('#highlight[привет]'));

      controller.setHighlight(kHighlightGreen);
      expect(saved, contains('#highlight(fill: $kHighlightGreen)[привет]'));

      controller.toggleHighlight();
      expect(saved, contains('привет'));
      expect(saved, isNot(contains('#highlight')));

      const customFillSource =
          '#highlight(fill: gradient.linear(red, blue))[x]';
      expect(
        TyLogDocument.parse(customFillSource).toSource(),
        customFillSource,
      );
    },
  );

  test(
    'bold, strike, and highlight combine and round-trip mono-innermost, '
    'highlight-outermost',
    () {
      final document = TyLogDocument.parse('combo');
      const selection = TextSelection(baseOffset: 0, extentOffset: 5);
      document.toggle(selection, bold: true);
      document.toggle(selection, strike: true);
      document.toggle(selection, highlight: kHighlightYellow);

      final source = document.toSource();
      expect(source, '#highlight(fill: $kHighlightYellow)[#strike[#strong[combo]]]');

      final reparsed = TyLogDocument.parse(source);
      expect(reparsed.visibleText, document.visibleText);
      expect(reparsed.toSource(), source);
    },
  );

  test(
    '== level headings round-trip verbatim and setHeading applies a chosen level',
    () {
      const source = '== Section\n\nBody text';
      final document = TyLogDocument.parse(source);
      expect(document.toSource(), source);
      expect(document.blocks.first.headingLevel, 2);

      final saved = <String>[];
      final controller = TyLogEditingController(
        source: 'plain text',
        onSourceChanged: saved.add,
        onError: (error) => fail('$error'),
        onProtectedTap: (_) {},
      );
      addTearDown(controller.dispose);
      controller.selection = const TextSelection.collapsed(offset: 0);

      controller.setHeading(level: 3);
      expect(saved.last, startsWith('=== '));
    },
  );

  test('setNumberedList emits a + prefixed line', () {
    final saved = <String>[];
    final controller = TyLogEditingController(
      source: 'item',
      onSourceChanged: saved.add,
      onError: (error) => fail('$error'),
      onProtectedTap: (_) {},
    );
    addTearDown(controller.dispose);
    controller.selection = const TextSelection.collapsed(offset: 4);

    controller.setNumberedList();
    expect(controller.text, '1. item');
    expect(saved.last, startsWith('+ '));
  });

  test('clearFormatting over a bold+italic selection produces plain text', () {
    final saved = <String>[];
    final controller = TyLogEditingController(
      source: '#strong[#emph[x]]',
      onSourceChanged: saved.add,
      onError: (error) => fail('$error'),
      onProtectedTap: (_) {},
    );
    addTearDown(controller.dispose);
    controller.selection = const TextSelection(baseOffset: 0, extentOffset: 1);

    controller.clearFormatting();

    expect(saved.last, 'x');
  });

  testWidgets(
    'long-press on Heading 1 shows a level menu and applies H2',
    (tester) async {
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
            body: TyLogRichEditor(controller: controller, onInsert: () async {}),
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('rich-journal-editor')));
      await tester.pump();
      controller.selection = const TextSelection.collapsed(offset: 0);

      await tester.longPress(
        find.byTooltip('Heading 1 (long-press for more levels)'),
      );
      await tester.pumpAndSettle();

      expect(find.text('Heading 2'), findsOneWidget);
      await tester.tap(find.text('Heading 2'));
      await tester.pumpAndSettle();

      expect(saved, contains('== '));
    },
  );
}
