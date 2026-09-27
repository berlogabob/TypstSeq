import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/rich_editor.dart';

const _header = '#show: tylog.note.with(id: "w", title: "Window")\n';

String _doc(int paragraphs) =>
    _header +
    List<String>.generate(
      paragraphs,
      (i) => i % 7 == 3
          ? '= Heading $i'
          : i % 5 == 1
          ? 'Para $i with *bold* and _italic_ text.'
          : 'Para $i plain text.',
    ).join('\n\n');

TyLogEditingController _main(String source, [List<String>? saved]) =>
    TyLogEditingController(
      source: source,
      onSourceChanged: (s) => saved?.add(s),
      onError: (error) => fail('$error'),
      onProtectedTap: (_) {},
    );

/// Types [insert] at the window caret the way EditableText does: a new
/// value with the text spliced in and the caret after it.
void _type(TextEditingController field, String insert) {
  final value = field.value;
  final at = value.selection.baseOffset;
  final text = value.text.replaceRange(
    at,
    value.selection.extentOffset,
    insert,
  );
  field.value = TextEditingValue(
    text: text,
    selection: TextSelection.collapsed(offset: at + insert.length),
  );
}

void main() {
  test('window covers only blocks around the caret', () {
    final main = _main(_doc(60));
    addTearDown(main.dispose);
    final window = TyLogWindowController(main);
    addTearDown(window.dispose);
    // No caret yet: the window opens at the top, like the plain field.
    expect(window.start, 0);
    expect('\n'.allMatches(window.text).length, lessThanOrEqualTo(20));
    expect(window.text, main.text.substring(window.start, window.end));
    expect(window.text.length, lessThan(main.text.length ~/ 4));
  });

  test('edits through the window equal the same edits on the model', () {
    final viaWindow = _main(_doc(60));
    final direct = _main(_doc(60));
    addTearDown(viaWindow.dispose);
    addTearDown(direct.dispose);
    final window = TyLogWindowController(viaWindow);
    addTearDown(window.dispose);

    // Caret into the middle of the document, then a mix of edits: typing,
    // a paragraph split (Enter twice), a backspace merge and a paste.
    final target = viaWindow.document.blockRanges[30].start + 4;
    viaWindow.selection = TextSelection.collapsed(offset: target);
    direct.selection = TextSelection.collapsed(offset: target);
    expect(window.start, lessThanOrEqualTo(target));
    expect(window.end, greaterThanOrEqualTo(target));

    for (final (edit, insert) in [
      ('type', 'hello '),
      ('enter', '\n\n'),
      ('type', 'new paragraph'),
      ('paste', ' pasted *text* here'),
    ]) {
      _type(window, insert);
      _type(direct, insert);
      expect(viaWindow.text, direct.text, reason: edit);
      expect(viaWindow.selection, direct.selection, reason: edit);
      expect(window.text, viaWindow.text.substring(window.start, window.end));
    }
    // Backspace at the start of a paragraph merges it into the previous one.
    for (final field in [window, direct]) {
      final value = field.value;
      final caret = value.selection.baseOffset;
      final lineStart = value.text.lastIndexOf('\n', caret - 1) + 1;
      field.value = TextEditingValue(
        text: value.text.replaceRange(lineStart - 1, lineStart, ''),
        selection: TextSelection.collapsed(offset: lineStart - 1),
      );
    }
    expect(viaWindow.document.toSource(), direct.document.toSource());
  });

  test('moving the caret far away recenters the window', () {
    final main = _main(_doc(60));
    addTearDown(main.dispose);
    final window = TyLogWindowController(main);
    addTearDown(window.dispose);
    final revisions = window.windowRevision.value;
    main.selection = TextSelection.collapsed(offset: main.text.length);
    expect(window.end, main.text.length);
    expect(window.start, greaterThan(main.text.length ~/ 2));
    expect(window.windowRevision.value, greaterThan(revisions));
    expect(
      window.start + window.selection.baseOffset,
      main.selection.baseOffset,
    );
  });

  test('an active composition never recenters the window', () {
    final main = _main(_doc(60));
    addTearDown(main.dispose);
    final window = TyLogWindowController(main);
    addTearDown(window.dispose);
    main.selection = TextSelection.collapsed(offset: main.text.length);
    final (start, end) = (window.start, window.end);
    final value = window.value;
    final at = value.selection.baseOffset;
    window.value = TextEditingValue(
      text: value.text.replaceRange(at, at, 'かな'),
      selection: TextSelection.collapsed(offset: at + 2),
      composing: TextRange(start: at, end: at + 2),
    );
    expect(
      main.value.composing,
      TextRange(start: window.start + at, end: window.start + at + 2),
    );
    main.value = main.value.copyWith(
      selection: const TextSelection.collapsed(offset: 0),
    );
    expect(window.start, start);
    expect(window.end, greaterThanOrEqualTo(end));
  });

  test('a selection spanning the document expands the window', () {
    final main = _main(_doc(40));
    addTearDown(main.dispose);
    final window = TyLogWindowController(main);
    addTearDown(window.dispose);
    main.selection = TextSelection(
      baseOffset: 0,
      extentOffset: main.text.length,
    );
    expect(window.start, 0);
    expect(window.end, main.text.length);
    expect(window.text, main.text);
  });

  test('undo through the model keeps the window consistent', () {
    final main = _main(_doc(40));
    addTearDown(main.dispose);
    final window = TyLogWindowController(main);
    addTearDown(window.dispose);
    main.selection = TextSelection.collapsed(offset: main.text.length);
    final before = main.text;
    _type(window, 'abc');
    expect(main.text, isNot(before));
    main.undo();
    expect(main.text, before);
    expect(window.text, main.text.substring(window.start, window.end));
  });

  test('one long paragraph is windowed by lines, not whole', () {
    final lines = List<String>.generate(900, (i) => 'Line $i of one paragraph');
    final main = _main('$_header#strong[Formatted] start\n${lines.join('\n')}');
    addTearDown(main.dispose);
    expect(main.document.blocks.length, lessThanOrEqualTo(2));
    main.selection = TextSelection.collapsed(offset: main.text.length);
    final window = TyLogWindowController(main);
    addTearDown(window.dispose);
    expect(window.text.length, lessThan(main.text.length ~/ 20));
    final direct = _main(
      '$_header#strong[Formatted] start\n${lines.join('\n')}',
    );
    addTearDown(direct.dispose);
    direct.selection = TextSelection.collapsed(offset: direct.text.length);
    for (final insert in ['\nframe-1', ' more', '\n\nnew block']) {
      _type(window, insert);
      _type(direct, insert);
    }
    expect(main.document.toSource(), direct.document.toSource());
  });

  test('appending at the end keeps the window bounded', () {
    final main = _main(_doc(20));
    addTearDown(main.dispose);
    main.selection = TextSelection.collapsed(offset: main.text.length);
    final window = TyLogWindowController(main);
    addTearDown(window.dispose);
    for (var i = 0; i < 200; i++) {
      final text = '${main.text}\nframe-$i';
      main.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
    }
    expect('\n'.allMatches(window.text).length, lessThanOrEqualTo(20));
    expect(window.end, main.text.length);
  });

  test('long lines split into units at spaces', () {
    final text = List.filled(200, 'word').join(' ');
    final breaks = TyLogWindowController.softBreaks(text, 0, text.length);
    expect(breaks, hasLength(text.length ~/ kWindowUnitChars));
    for (final (k, b) in breaks.indexed) {
      expect(text[b - 1], ' ');
      expect(b - (k + 1) * kWindowUnitChars, inInclusiveRange(1, 6));
    }
    final at = breaks.lastIndexWhere((b) => b <= 700);
    expect(TyLogWindowController.unitStart(text, 700), breaks[at]);
    expect(TyLogWindowController.unitEnd(text, 700), breaks[at + 1]);
    expect(TyLogWindowController.unitStart(text, 5), 0);
    expect(TyLogWindowController.unitEnd(text, 990), text.length);
  });

  test('a long growing paragraph keeps the window bounded', () {
    final source = '${_header}start\n${List.filled(180, 'word').join(' ')}';
    final viaWindow = _main(source);
    final direct = _main(source);
    addTearDown(viaWindow.dispose);
    addTearDown(direct.dispose);
    viaWindow.selection = TextSelection.collapsed(
      offset: viaWindow.text.length,
    );
    direct.selection = TextSelection.collapsed(offset: direct.text.length);
    final window = TyLogWindowController(viaWindow);
    addTearDown(window.dispose);
    for (var i = 0; i < 300; i++) {
      final insert = i % 5 == 4 ? ' ' : 'x';
      _type(window, insert);
      _type(direct, insert);
      expect(window.text.length, lessThanOrEqualTo(kWindowMaxChars + 400));
    }
    expect(window.end, viaWindow.text.length);
    expect(window.text, viaWindow.text.substring(window.start, window.end));
    expect(viaWindow.document.toSource(), direct.document.toSource());
    // Moving to the top and back recenters within the long line.
    viaWindow.selection = const TextSelection.collapsed(offset: 0);
    expect(window.start, 0);
    viaWindow.selection = TextSelection.collapsed(offset: 700);
    expect(window.start, lessThanOrEqualTo(700));
    expect(window.end, greaterThanOrEqualTo(700));
  });
}
