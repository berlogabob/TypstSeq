import 'dart:io';

import 'package:test/test.dart';
import 'package:tylog_core/tylog_core.dart';

void main() {
  group('tag synonyms', _synonymTests);
  group('tag synonym file', _synonymFileTests);
  group('stale cache', _staleCacheTests);

  test('scanNote recovers legacy journal-day:: dates and source:: links', () {
    const source = '''
#show: tylog.note.with(id: "a", title: "A", tags: ())

journal-day:: [[2026-05-26]]
source:: [[shazoo.ru]]
''';

    final note = scanNote('notes/a.typ', source);

    expect(note.dateRefs.map((d) => d.date), contains('2026-05-26'));
    expect(note.outgoingLinks, contains('shazoo.ru'));
  });

  test('scanNote recovers legacy Logseq `tags:: [[..]]` wiki-link tags', () {
    const source = '''
#show: tylog.note.with(id: "godot", title: "Godot vs Unity", tags: ())

tags:: [[Godot]] [[Unity]] [[игровые движки]]
''';

    final note = scanNote('notes/godot.typ', source);

    // Tags are folded to one canonical spelling when indexed, so clustering
    // does not see `Godot` and `godot` as unrelated concepts.
    expect(note.tags, containsAll(['godot', 'unity', 'игровые-движки']));
  });

  test('scanNote recovers comma-separated legacy tags', () {
    const source = '''
#show: tylog.note.with(id: "a", title: "A", tags: ("kept",))

tags:: ESP32, Home-Assistant
''';

    final note = scanNote('notes/a.typ', source);

    expect(note.tags, containsAll(['kept', 'esp32', 'home-assistant']));
  });

  test('scanNote recovers `tags:: #A #B` hashtag tags', () {
    // Logseq's most common form. It has no wiki-links and no commas, so it
    // used to fall through to the comma split and become ONE tag holding the
    // whole line — which then matched nothing and left the note unclustered.
    const source = '''
#show: tylog.note.with(id: "a", title: "A", tags: ())

tags:: #Python #разработка
''';

    final note = scanNote('notes/a.typ', source);

    expect(note.tags, ['python', 'разработка']);
  });

  test('a hashtag tag may contain spaces', () {
    // Split on the '#' delimiter, not on whitespace: Logseq tags are free text
    // up to the next '#', so this is two tags rather than four.
    const source = '''
#show: tylog.note.with(id: "a", title: "A", tags: ())

tags:: #библиотеки Python #советы для разработчиков
''';

    final note = scanNote('notes/a.typ', source);

    expect(note.tags, ['библиотеки-python', 'советы-для-разработчиков']);
  });

  test('markdown-import escaping is stripped before tags are parsed', () {
    // tylog_import_core escapes Typst's specials when it writes body text, so
    // the recovered line arrives as `\\#Python`. Left in, the backslash becomes
    // part of the tag and it matches nothing.
    const source = '''
#show: tylog.note.with(id: "a", title: "A", tags: ())

tags:: \\#Python \\#машинное\\-обучение
''';

    final note = scanNote('notes/a.typ', source);

    expect(note.tags, ['python', 'машинное-обучение']);
  });

  test(
    'queried path merges legacy tags even when the inspector returns none',
    () async {
      final root = await Directory.systemTemp.createTemp('tylog_legacy_');
      addTearDown(() => root.delete(recursive: true));
      final storage = LocalVaultStorage(root);
      await storage.writeText(
        'notes/godot.typ',
        '#show: tylog.note.with(id: "godot", title: "Godot", tags: ())\n'
            '\ntags:: [[Godot]] [[Unity]]\n',
      );

      final index = await scanVaultStorage(
        storage,
        inspector: _EmptyTagsInspector(),
      );

      expect(index.notes.single.tags, containsAll(['godot', 'unity']));
    },
  );
}

/// Stands in for a successful Typst query that carries no tags — proving the
/// legacy recovery is folded into the queried path, not only the fallback.
class _EmptyTagsInspector implements TypstInspector {
  @override
  Future<List<TypstMetadataRecord>> inspect(TypstDocumentInput input) async => [
    TypstMetadataRecord(
      label: '<tylog-note>',
      value: {
        'schema': 1,
        'entity': 'note',
        'id': 'godot',
        'title': 'Godot',
        'tags': const <String>[],
      },
    ),
  ];
}

/// Synonym folding: variants of one concept must land on one tag, or each
/// spelling clusters separately (`ai` / `искусственный-интеллект` / `ии` were
/// 270 notes in three clusters).
void _synonymTests() {
  const synonyms = {'искусственный-интеллект': 'ai', 'ии': 'ai', 'llms': 'llm'};

  NoteRef scan(String tags, {Map<String, String> map = synonyms}) => scanNote(
    'notes/a.typ',
    '#show: tylog.note.with(id: "a", title: "A", tags: ($tags))\n',
    synonyms: map,
  );

  test('variants fold onto the canonical tag', () {
    expect(scan('"Искусственный интеллект", "ИИ"').tags, ['ai']);
  });

  test('an unmapped tag is left alone, still case-folded', () {
    expect(scan('"Godot", "LLMs"').tags, ['godot', 'llm']);
  });

  test('no map means no merging', () {
    expect(scan('"ии", "ai"', map: const {}).tags, ['ai', 'ии']);
  });

  test('synonyms reach body-recovered tags too', () {
    final note = scanNote(
      'notes/a.typ',
      '#show: tylog.note.with(id: "a", title: "A", tags: ())\n\n'
      'tags:: #ИИ #Godot\n',
      synonyms: synonyms,
    );
    expect(note.tags, ['ai', 'godot']);
  });

  test('a chain in the map is followed exactly one hop', () {
    // Chained merges are how a synonym set drifts into a neighbouring concept.
    // `a` resolves to `b` and stops, even though `b -> c` is also present.
    final note = scan('"a"', map: const {'a': 'b', 'b': 'c'});
    expect(note.tags, ['b']);
  });
}

/// The map is a file in a synced vault, so it can be absent, half-written or
/// hand-edited into nonsense. None of that may fail a scan.
void _synonymFileTests() {
  Future<VaultStorage> vault(String? contents) async {
    final root = await Directory.systemTemp.createTemp('tylog_syn_');
    addTearDown(() => root.delete(recursive: true));
    final storage = LocalVaultStorage(root);
    if (contents != null) {
      await storage.writeText('_system/tag-synonyms.json', contents);
    }
    return storage;
  }

  test('a well-formed map is loaded', () async {
    final storage = await vault('{"schema":1,"synonyms":{"ИИ":"AI"}}');
    // Keys and values are folded, so the file may be written in any casing.
    expect(await loadTagSynonyms(storage), {'ии': 'ai'});
  });

  test('absent, corrupt, or wrong-shaped files yield no synonyms', () async {
    expect(await loadTagSynonyms(await vault(null)), isEmpty);
    expect(await loadTagSynonyms(await vault('not json {')), isEmpty);
    expect(await loadTagSynonyms(await vault('[]')), isEmpty);
    expect(await loadTagSynonyms(await vault('{"synonyms":"nope"}')), isEmpty);
    expect(await loadTagSynonyms(await vault('{}')), isEmpty);
  });

  test('self-mappings and blanks are dropped', () async {
    final storage = await vault(
      '{"synonyms":{"ai":"ai","":"ai","x":"","ии":"ai"}}',
    );
    expect(await loadTagSynonyms(storage), {'ии': 'ai'});
  });

  test('a scan picks the map up from the vault', () async {
    final storage = await vault('{"synonyms":{"ии":"ai"}}');
    await storage.writeText(
      'notes/a.typ',
      '#show: tylog.note.with(id: "a", title: "A", tags: ("ИИ",))\n',
    );

    final index = await scanVaultStorage(storage);

    expect(index.notes.single.tags, ['ai']);
  });
}

/// A note whose Typst query fails keeps its cached entry, which is right for a
/// transient hiccup and wrong across a schema bump: the cached tags were
/// derived by rules that no longer apply.
class _FailingInspector implements TypstInspector {
  @override
  Future<List<TypstMetadataRecord>> inspect(TypstDocumentInput input) async =>
      throw StateError('inspect failed');
}

void _staleCacheTests() {
  Future<VaultStorage> vaultWith(String tags) async {
    final root = await Directory.systemTemp.createTemp('tylog_stale_');
    addTearDown(() => root.delete(recursive: true));
    final storage = LocalVaultStorage(root);
    await storage.writeText(
      'notes/a.typ',
      '#show: tylog.note.with(id: "a", title: "A", tags: ($tags))\n',
    );
    return storage;
  }

  test('an old-schema cached note is re-derived, not resurrected', () async {
    final storage = await vaultWith('"ии"');
    // Stands in for an index written before the synonym map existed.
    final old = VaultIndex(
      version: kVaultIndexVersion - 1,
      notesByPath: {
        'notes/a.typ': const NoteRef(
          id: 'a',
          path: 'notes/a.typ',
          title: 'A',
          outgoingLinks: [],
          tags: ['ии'],
        ),
      },
      backlinksByTarget: const {},
    );
    await storage.writeText(
      '_system/tag-synonyms.json',
      '{"synonyms":{"ии":"ai"}}',
    );

    final index = await scanVaultStorage(
      storage,
      previous: old,
      inspector: _FailingInspector(),
    );

    expect(
      index.notes.single.tags,
      ['ai'],
      reason: 'the failed query must not bring back pre-merge tags',
    );
  });

  test('a current-schema cached note still survives a failed query', () async {
    final storage = await vaultWith('"kept"');
    // Carrying the identity of the bytes it describes, as a real cached entry
    // always does — the scan stamps one. Without it nothing can tell this
    // entry apart from metadata left over from a different version of the
    // file, which is the case that must NOT survive a failed query.
    final current = VaultIndex(
      notesByPath: {
        'notes/a.typ': NoteRef(
          id: 'a',
          path: 'notes/a.typ',
          title: 'Queried title',
          outgoingLinks: const [],
          tags: const ['kept'],
          contentHash: await storage.hash('notes/a.typ'),
          metadataSource: 'typst-query',
        ),
      },
      backlinksByTarget: const {},
    );

    final index = await scanVaultStorage(
      storage,
      previous: current,
      inspector: _FailingInspector(),
    );

    expect(
      index.notes.single.title,
      'Queried title',
      reason: 'a transient failure must not downgrade a good queried note',
    );
  });
}
