import 'dart:io';

import 'package:test/test.dart';
import 'package:tylog_core/tylog_core.dart';

void main() {
  test('scanNote recovers legacy journal-day:: dates and source:: links', () {
    const source = '''
#show: tylog.note.with(id: "a", title: "A", tags: ())

journal-day:: [[2026-05-26]]
source:: [[shazoo.ru]]
''';

    final note = scanNote('articles/a.typ', source);

    expect(note.dateRefs.map((d) => d.date), contains('2026-05-26'));
    expect(note.outgoingLinks, contains('shazoo.ru'));
  });

  test('scanNote recovers legacy Logseq `tags:: [[..]]` wiki-link tags', () {
    const source = '''
#show: tylog.note.with(id: "godot", title: "Godot vs Unity", tags: ())

tags:: [[Godot]] [[Unity]] [[игровые движки]]
''';

    final note = scanNote('articles/godot.typ', source);

    // Tags are folded to one canonical spelling when indexed, so clustering
    // does not see `Godot` and `godot` as unrelated concepts.
    expect(note.tags, containsAll(['godot', 'unity', 'игровые-движки']));
  });

  test('scanNote recovers comma-separated legacy tags', () {
    const source = '''
#show: tylog.note.with(id: "a", title: "A", tags: ("kept",))

tags:: ESP32, Home-Assistant
''';

    final note = scanNote('articles/a.typ', source);

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

    final note = scanNote('articles/a.typ', source);

    expect(note.tags, ['python', 'разработка']);
  });

  test('a hashtag tag may contain spaces', () {
    // Split on the '#' delimiter, not on whitespace: Logseq tags are free text
    // up to the next '#', so this is two tags rather than four.
    const source = '''
#show: tylog.note.with(id: "a", title: "A", tags: ())

tags:: #библиотеки Python #советы для разработчиков
''';

    final note = scanNote('articles/a.typ', source);

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

    final note = scanNote('articles/a.typ', source);

    expect(note.tags, ['python', 'машинное-обучение']);
  });

  test(
    'queried path merges legacy tags even when the inspector returns none',
    () async {
      final root = await Directory.systemTemp.createTemp('tylog_legacy_');
      addTearDown(() => root.delete(recursive: true));
      final storage = LocalVaultStorage(root);
      await storage.writeText(
        'articles/godot.typ',
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
