import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('extension pack docs define and parse the published JSON contracts', () {
    final document = File('docs/extension-packs.md').readAsStringSync();
    for (final heading in [
      'Manifest',
      'Install record',
      'Update channel',
      'Mounts',
      'Write boundaries',
    ]) {
      expect(document, contains('## $heading'));
    }

    final examples = RegExp(
      r'```json\n([\s\S]*?)\n```',
    ).allMatches(document).map((match) => match.group(1)!).toList();
    expect(examples, hasLength(3));
    final decoded = examples.map((example) => jsonDecode(example)).toList();
    expect(decoded[0], containsPair('schema', 1));
    expect(decoded[1], containsPair('files', isA<Map>()));
    expect(decoded[2], isA<List>());
  });
}
