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

  group('parseBibtexBibliography', () {
    test('parses BBT-style entries with braces, quotes, and bare values', () {
      final entries = parseBibtexBibliography('''
@comment{jabref-meta: databaseType:biblatex;}
@string{acm = {ACM Press}}
@article{smith:2026word,
  title = {The {BIG} Solar Desalination Result},
  author = {Smith, Jane and Doe, John},
  year = 2026,
  journaltitle = {Nature},
}
@book(ivanov_2025,
  title = "Исследование памяти",
  author = {Пётр Иванов},
  date = {2025-03-01},
)
''');
      expect(entries.map((e) => e.key), ['ivanov_2025', 'smith:2026word']);
      final smith = entries.last;
      expect(smith.title, 'The BIG Solar Desalination Result');
      expect(smith.author, 'Smith');
      expect(smith.year, '2026');
      expect(smith.type, 'article');
      expect(smith.source, 'zotero');
      final ivanov = entries.first;
      expect(ivanov.title, 'Исследование памяти');
      expect(ivanov.author, 'Иванов');
      expect(ivanov.year, '2025');
    });

    test('skips malformed entries instead of throwing', () {
      final entries = parseBibtexBibliography('''
@article{broken-no-title,
  author = {Nobody},
}
@garbage
@article{ok,
  title = {Fine},
}
''');
      expect(entries.map((e) => e.key), ['ok']);
      expect(entries.single.type, 'article');
    });

    test('empty input yields no entries', () {
      expect(parseBibtexBibliography(''), isEmpty);
    });
  });
}
