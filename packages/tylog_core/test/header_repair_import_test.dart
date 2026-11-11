import 'package:test/test.dart';
import 'package:tylog_core/tylog_core.dart';

const imp = '#import "/_system/tylog.typ" as tylog\n\n';
const note = '#show: tylog.note.with(id: "a", title: "A")\nBody\n';

void main() {
  group('withTylogImport', () {
    test('adds the import before a note without it', () {
      final actual = withTylogImport('a.typ', note);
      expect(actual, equals(imp + note));
    });

    test('skips adding for a markdown path', () {
      final actual = withTylogImport('a.md', note);
      expect(actual, equals(note));
    });

    test('leaves text that already contains the import unchanged', () {
      final input = '#import "/_system/tylog.typ" as tylog\n$note';
      final actual = withTylogImport('a.typ', input);
      expect(actual, equals(input));
    });

    test('leaves plain text without a note unchanged', () {
      final actual = withTylogImport('a.typ', 'plain\n');
      expect(actual, equals('plain\n'));
    });

    test('is idempotent when called twice', () {
      final actual = withTylogImport('a.typ', withTylogImport('a.typ', note));
      expect(actual, equals(imp + note));
    });
  });
}
