import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/bibliography.dart';

void main() {
  test('Hayagriva YAML entries are validated and sorted', () {
    final entries = parseHayagrivaBibliography('''
smith-2026:
  type: article
  title: Research Infrastructure
alpha:
  type: book
  title: Foundations
''');
    expect(entries.map((entry) => entry.key), ['alpha', 'smith-2026']);
    expect(entries.last.title, 'Research Infrastructure');
  });

  test('Hayagriva entries require type and title', () {
    expect(
      () => parseHayagrivaBibliography('broken:\n  title: Missing type\n'),
      throwsFormatException,
    );
  });
}
