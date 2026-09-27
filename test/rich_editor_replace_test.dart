import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/rich_editor.dart';

const _header = '#show: tylog.note.with(id: "r", title: "R")\n';

void main() {
  test('typing at a style boundary inherits the style before it', () {
    final doc = TyLogDocument.parse('$_header*bold*plain');
    doc.replace(4, 4, 'X');
    expect(doc.visibleText, 'boldXplain');
    final parts = doc.blocks.single.parts;
    expect(parts.first.text, 'boldX');
    expect(parts.first.style.bold, isTrue);
    expect(parts.last.style.bold, isFalse);
  });

  test('typing into an empty paragraph', () {
    final doc = TyLogDocument.parse('${_header}a\n\n');
    final at = doc.visibleText.length;
    doc.replace(at, at, 'hi');
    expect(doc.visibleText, endsWith('hi'));
  });

  test('random edits in a formatted block splice exactly and round-trip', () {
    final random = Random(5);
    final doc = TyLogDocument.parse(
      '${_header}start *bold* mid _it_ `code` end ${'word ' * 40}tail',
    );
    var expected = doc.visibleText;
    for (var i = 0; i < 300; i++) {
      final a = random.nextInt(expected.length + 1);
      final b = min(expected.length, a + random.nextInt(4));
      final insert = ['', 'x', 'yz', ' '][random.nextInt(4)];
      doc.replace(a, b, insert);
      expected = expected.replaceRange(a, b, insert);
      expect(doc.visibleText, expected, reason: 'edit $i');
      expect(
        TyLogDocument.parse(doc.toSource()).visibleText,
        expected,
        reason: 'round-trip $i',
      );
    }
  });
}
