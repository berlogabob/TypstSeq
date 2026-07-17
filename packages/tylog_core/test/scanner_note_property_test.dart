import 'package:test/test.dart';
import 'package:tylog_core/tylog_core.dart';

void main() {
  group('replaceNoteProperty', () {
    test('overwrites an existing key without touching other fields', () {
      const source = '''
#show: tylog.note.with(
  id: "smith-2026",
  title: "Smith 2026",
  kind: "article",
  date: none,
  tags: (),
  aliases: (),
  project: none,
  properties: ("status": "unread", "citation-key": "smith-2026",),
)
''';
      final updated = replaceNoteProperty(source, 'status', 'reading');

      expect(updated, contains('"status": "reading"'));
      expect(updated, contains('"citation-key": "smith-2026"'));
      expect(updated, isNot(contains('"status": "unread"')));
    });

    test('inserts a new key into an existing non-empty properties dict', () {
      const source = '''
#show: tylog.note.with(
  id: "a",
  title: "A",
  kind: "article",
  date: none,
  tags: (),
  aliases: (),
  project: none,
  properties: ("citation-key": "smith-2026",),
)
''';
      final updated = replaceNoteProperty(source, 'status', 'read');

      expect(updated, contains('"citation-key": "smith-2026"'));
      expect(updated, contains('"status": "read"'));
    });

    test('inserts a key into an empty properties dict', () {
      const source = '''
#show: tylog.note.with(
  id: "a",
  title: "A",
  kind: "article",
  date: none,
  tags: (),
  aliases: (),
  project: none,
  properties: (:),
)
''';
      final updated = replaceNoteProperty(source, 'status', 'unread');

      expect(updated, contains('"status": "unread"'));
    });

    test('appends a properties field when the header has none', () {
      const source = '''
#show: tylog.note.with(
  id: "a",
  title: "A",
  kind: "article",
  date: none,
  tags: (),
  aliases: (),
  project: none,
)
''';
      final updated = replaceNoteProperty(source, 'status', 'unread');

      expect(updated, contains('properties: ("status": "unread",)'));
    });

    test('does not corrupt a title containing a status:-shaped literal', () {
      const source = '''
#show: tylog.note.with(
  id: "a",
  title: "Article about status: \\"unread\\" tracking",
  kind: "article",
  date: none,
  tags: (),
  aliases: (),
  project: none,
  properties: ("status": "unread",),
)
''';
      final updated = replaceNoteProperty(source, 'status', 'read');

      expect(updated, contains('"status": "read"'));
      expect(
        updated,
        contains(r'title: "Article about status: \"unread\" tracking"'),
      );
    });

    test('leaves body content after the header untouched', () {
      const source = '''
#show: tylog.note.with(
  id: "a",
  title: "A",
  kind: "article",
  date: none,
  tags: (),
  aliases: (),
  project: none,
  properties: ("status": "unread",),
)

= A
Body text here.
''';
      final updated = replaceNoteProperty(source, 'status', 'read');

      expect(updated, contains('= A\nBody text here.'));
    });
  });
}
