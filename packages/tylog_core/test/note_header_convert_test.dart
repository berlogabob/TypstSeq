import 'package:test/test.dart';
import 'package:tylog_core/tylog_core.dart';

void main() {
  _repairTests();
  group('convert a legacy note to a managed header', () {
    test('rebuilds tylog.note.with(...) from a NoteRef, body untouched', () {
      // A fallback-parsed note: no managed header, just body content.
      const legacy = '#import "/_system/tylog.typ" as tylog\n\n'
          'Some body text.\n- a bullet\n';
      const note = NoteRef(
        id: 'barbara',
        path: 'notes/Barbara.typ',
        title: 'Barbara',
        kind: 'person',
        outgoingLinks: [],
        tags: ['contact'],
      );

      final updated = replaceNoteHeader(
        legacy,
        NoteMetadataDraft.fromNote(note),
      );

      expect(updated, contains('#show: tylog.note.with('));
      expect(updated, contains('id: "barbara"'));
      expect(updated, contains('kind: "person"'));
      expect(updated, contains('title: "Barbara"'));
      expect(updated, contains('tags: ("contact",)'));
      // Body is preserved verbatim, header sits right after the import.
      expect(updated, contains('as tylog\n#show: tylog.note.with('));
      expect(updated, contains('Some body text.\n- a bullet'));
    });

    test('adds the tylog import when a legacy note never had one', () {
      // A hand-authored .typ with raw styling and no import/header.
      const raw = '#set page(margin: 2cm)\n\n= Notes\nBody.';
      const note = NoteRef(
        id: 'device-test',
        path: 'notes/device-test.typ',
        title: 'device-test',
        outgoingLinks: [],
      );

      final updated = replaceNoteHeader(
        raw,
        NoteMetadataDraft.fromNote(note),
      );

      // Import must precede the managed header, and the raw body is kept.
      expect(updated, startsWith('#import "/_system/tylog.typ" as tylog'));
      expect(updated, contains('#show: tylog.note.with('));
      expect(
        updated.indexOf('#import'),
        lessThan(updated.indexOf('#show: tylog.note.with(')),
      );
      expect(updated, contains('#set page(margin: 2cm)'));
      // Exactly one import even when re-run on the now-managed note.
      final again = replaceNoteHeader(updated, NoteMetadataDraft.fromNote(note));
      expect('#import "/_system/tylog.typ"'.allMatches(again).length, 1);
    });

    test('replaces an existing header instead of stacking a second one', () {
      const withHeader = '#import "/_system/tylog.typ" as tylog\n'
          '#show: tylog.note.with(\n  id: "x",\n  title: "Old",\n  kind: "note",\n)\n\nBody.';
      const note = NoteRef(
        id: 'x',
        path: 'notes/x.typ',
        title: 'New Title',
        kind: 'article',
        outgoingLinks: [],
      );

      final updated = replaceNoteHeader(
        withHeader,
        NoteMetadataDraft.fromNote(note),
      );

      expect('#show: tylog.note.with('.allMatches(updated).length, 1);
      expect(updated, contains('title: "New Title"'));
      expect(updated, contains('kind: "article"'));
    });
  });
}

void _repairTests() {
  group('repairArticleTypst', () {
    test('breaks inline-function field access (.word)', () {
      expect(repairArticleTypst('#emph[confident guessing].Instead of'),
          '#emph[confident guessing]. Instead of');
      expect(repairArticleTypst('#strong[x].Нужно'), '#strong[x]. Нужно');
    });
    test('spaces a content block abutting ( or [ (not legit )[ )', () {
      expect(repairArticleTypst('#link("u")[label](2024).'),
          '#link("u")[label] (2024).');
      // Legit link call syntax `)[` must be untouched.
      expect(repairArticleTypst('#link("u")[label]'), '#link("u")[label]');
    });
    test('escapes bare emails but not those inside strings', () {
      expect(repairArticleTypst('write to andre@x.com please'),
          r'write to andre\@x.com please');
      expect(repairArticleTypst('#link("mailto:a@x.com")[a\\@x.com]'),
          '#link("mailto:a@x.com")[a\\@x.com]');
    });
    test('is idempotent and leaves clean prose alone', () {
      const clean = 'Just #emph[some] prose with a #link("u")[link] and text.';
      expect(repairArticleTypst(clean), clean);
      final once = repairArticleTypst('#emph[x].Word');
      expect(repairArticleTypst(once), once);
    });
  });
}
