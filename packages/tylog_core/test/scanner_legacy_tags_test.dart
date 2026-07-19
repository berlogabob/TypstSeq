import 'dart:io';

import 'package:test/test.dart';
import 'package:tylog_core/tylog_core.dart';

void main() {
  test('scanNote recovers legacy Logseq `tags:: [[..]]` wiki-link tags', () {
    const source = '''
#show: tylog.note.with(id: "godot", title: "Godot vs Unity", tags: ())

tags:: [[Godot]] [[Unity]] [[игровые движки]]
''';

    final note = scanNote('articles/godot.typ', source);

    expect(note.tags, containsAll(['Godot', 'Unity', 'игровые движки']));
  });

  test('scanNote recovers comma-separated legacy tags', () {
    const source = '''
#show: tylog.note.with(id: "a", title: "A", tags: ("kept",))

tags:: ESP32, Home-Assistant
''';

    final note = scanNote('articles/a.typ', source);

    expect(note.tags, containsAll(['kept', 'ESP32', 'Home-Assistant']));
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

      expect(index.notes.single.tags, containsAll(['Godot', 'Unity']));
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
