import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/app_mobile.dart';
import 'package:tylog_core/models.dart';

NoteRef _article(String id, {Map<String, Object?> properties = const {}}) =>
    NoteRef(
      id: id,
      path: 'articles/$id.typ',
      title: id,
      kind: 'article',
      outgoingLinks: const [],
      properties: properties,
    );

void main() {
  // Must match the private _autoRelatedMarker in app_mobile.dart.
  const marker = '// tylog:auto-related';
  const body = '#import "x"\n\n= Title\n\nBody text.';

  test('stripAutoRelated removes an appended block and is idempotent', () {
    final withBlock =
        '$body\n\n$marker\n== Related\n#tylog.ref-note("a")[A]\n';
    final stripped = stripAutoRelated(withBlock);
    expect(stripped, body, reason: 'block and its trailing whitespace removed');

    // Stripping the clean body again is a no-op.
    expect(stripAutoRelated(stripped), body);

    // Re-appending a *different* block then stripping returns to the same body —
    // this is what makes a repeated "Relink vault" idempotent, not duplicating.
    final reAppended =
        '$stripped\n\n$marker\n== Related\n#tylog.ref-note("b")[B]\n';
    expect(stripAutoRelated(reAppended), body);
  });

  // article-pipeline writes the block last, so nothing follows it today. If a
  // user types below their Related section, a relink must not silently delete
  // it — there is no error and nothing to undo.
  test('stripAutoRelated keeps content written after the block', () {
    final withTail =
        '$body\n\n$marker\n== Related\n'
        '- #tylog.ref-note("a")[A]\n\n= My own notes\n\nKeep this.\n';

    expect(stripAutoRelated(withTail), '$body\n\n= My own notes\n\nKeep this.');
  });

  test('stripAutoRelated leaves marker-free source untouched', () {
    const plain = '= Note\n\nNo related block here.';
    expect(stripAutoRelated(plain), plain);
  });

  test('relinkCandidates skips articles article-pipeline linked with an LLM', () {
    final notes = [
      _article('plain'),
      _article('llm', properties: {'llm_provider': 'ollama'}),
      _article('empty-provider', properties: {'llm_provider': ''}),
      // A non-string value must not throw the way a bare `as String?` would.
      _article('odd-provider', properties: {'llm_provider': 42}),
      const NoteRef(
        id: 'n',
        path: 'notes/n.typ',
        title: 'N',
        kind: 'note',
        outgoingLinks: [],
      ),
    ];

    expect(
      relinkCandidates(notes).map((n) => n.id),
      ['plain', 'empty-provider', 'odd-provider'],
      reason: 'only articles, and only those without real LLM-written links',
    );
  });
}
