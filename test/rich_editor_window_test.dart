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
    expect(window.last, main.document.blocks.length - 1);
    expect(window.last - window.first, lessThanOrEqualTo(8));
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
    main.selection = TextSelection.collapsed(
      offset: main.document.blockRanges[2].start,
    );
    expect(window.first, 0);
    expect(window.last, lessThan(10));
    expect(window.windowRevision.value, greaterThan(revisions));
    expect(window.selection.baseOffset, main.selection.baseOffset);
  });

  test('an active composition never recenters the window', () {
    final main = _main(_doc(60));
    addTearDown(main.dispose);
    final window = TyLogWindowController(main);
    addTearDown(window.dispose);
    main.selection = TextSelection.collapsed(offset: main.text.length);
    final (first, last) = (window.first, window.last);
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
    expect((window.first, window.last), (first, last));
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
    expect(window.first, 0);
    expect(window.last, main.document.blocks.length - 1);
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
}
