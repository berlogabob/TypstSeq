import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/models.dart';
import 'package:tylog/scanner.dart';

void main() {
  test('scanner extracts links, tags, and backlinks', () async {
    final dir = await Directory.systemTemp.createTemp('tylog_scanner_');
    addTearDown(() => dir.delete(recursive: true));

    await File('${dir.path}/A.typ').writeAsString('''#note(title: "A")
#tag("journal")
#wikilink("B")
#wikilink("B", display: "bee")
''');
    await File('${dir.path}/B.typ').writeAsString('#note(title: "B")');

    final index = await scanVault(dir);

    expect(index.notesByPath['A.typ']!.title, 'A');
    expect(index.notesByPath['A.typ']!.tags, ['journal']);
    expect(index.notesByPath['A.typ']!.outgoingLinks, ['B']);
    expect(index.backlinksByTarget['B.typ'], ['A.typ']);
  });

  test('bad Typst text does not crash scanner', () {
    final note = scanNote('Bad.typ', '#note(title: "Bad"');
    expect(note.title, 'Bad');
    expect(note.outgoingLinks, isEmpty);
  });

  test('link resolver prefers title then filename stem', () {
    final index = VaultIndex(
      notesByPath: {
        'pages/Real.typ': const NoteRef(
          path: 'pages/Real.typ',
          title: 'Display',
          outgoingLinks: [],
        ),
        'pages/Stem.typ': const NoteRef(
          path: 'pages/Stem.typ',
          title: 'Other',
          outgoingLinks: [],
        ),
      },
      backlinksByTarget: const {},
    );

    expect(resolveLinkPath(index, 'Display'), 'pages/Real.typ');
    expect(resolveLinkPath(index, 'Stem'), 'pages/Stem.typ');
    expect(resolveLinkPath(index, 'Missing'), isNull);
  });
}
