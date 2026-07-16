import 'package:test/test.dart';
import 'package:tylog_core/tylog_core.dart';

// Note: NoteRef.properties is only populated via the typst-query inspector
// path (`_queriedNote`); the pure fallback parser (`scanNote`/`_fallbackNote`)
// always reports `properties: {}` regardless of the raw header text. So
// `kind` is verified by re-parsing with `scanNote` (which the fallback path
// does read from the header), while the properties dictionary itself is
// verified against the migrated header's raw text.
void main() {
  group('migrateEntityTypeToKind', () {
    test('folds properties["type"] into kind when kind is generic', () {
      const source = '''
#import "@local/tylog:0.1.0": tylog
#show: tylog.note.with(
  id: "n1",
  title: "Alice",
  kind: "note",
  date: none,
  tags: (),
  aliases: (),
  project: none,
  properties: ("type": "person",),
)

Body text.
''';

      final migrated = migrateEntityTypeToKind(source);
      final note = scanNote('notes/n1.typ', migrated);

      expect(note.kind, 'person');
      expect(migrated, contains('kind: "person"'));
      expect(migrated, isNot(contains('"type"')));
    });

    test('is idempotent', () {
      const source = '''
#show: tylog.note.with(
  id: "n1",
  title: "Alice",
  kind: "note",
  properties: ("type": "person",),
)
''';

      final once = migrateEntityTypeToKind(source);
      final twice = migrateEntityTypeToKind(once);

      expect(twice, once);
    });

    test('leaves an already-specific kind unchanged (no type property)', () {
      const source = '''
#show: tylog.note.with(
  id: "p1",
  title: "Project One",
  kind: "project",
)
''';

      final migrated = migrateEntityTypeToKind(source);

      expect(migrated, source);
    });

    test('does not clobber an already-specific kind even with a type '
        'property present', () {
      const source = '''
#show: tylog.note.with(
  id: "loc1",
  title: "Somewhere",
  kind: "place",
  properties: ("type": "person",),
)
''';

      final migrated = migrateEntityTypeToKind(source);

      expect(migrated, source);
    });

    test('preserves other properties untouched', () {
      const source = '''
#show: tylog.note.with(
  id: "n1",
  title: "Alice",
  kind: "note",
  properties: ("type": "person", "role": "friend",),
)
''';

      final migrated = migrateEntityTypeToKind(source);
      final note = scanNote('notes/n1.typ', migrated);

      expect(note.kind, 'person');
      expect(migrated, contains('"role": "friend"'));
      expect(migrated, isNot(contains('"type"')));
    });
  });
}
