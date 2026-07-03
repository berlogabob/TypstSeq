import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/models.dart';
import 'package:tylog/scanner.dart';

void main() {
  test('scanner extracts links, tags, and backlinks', () async {
    final dir = await Directory.systemTemp.createTemp('tylog_scanner_');
    addTearDown(() => dir.delete(recursive: true));

    await File('${dir.path}/A.typ').writeAsString('''#note(
  id: "a-id",
  title: "A",
  tags: ("journal", "pkms"),
  aliases: ("alpha",),
  links: ("B",),
  files: ("manual-pdf",),
)
#tag("journal")
#wikilink("B")
#wikilink("B", display: "bee")
''');
    await File('${dir.path}/B.typ').writeAsString('#note(title: "B")');

    final index = await scanVault(dir);

    expect(index.notesByPath['A.typ']!.id, 'a-id');
    expect(index.notesByPath['A.typ']!.title, 'A');
    expect(index.notesByPath['A.typ']!.tags, ['journal', 'pkms']);
    expect(index.notesByPath['A.typ']!.aliases, ['alpha']);
    expect(index.notesByPath['A.typ']!.outgoingLinks, ['B']);
    expect(index.notesByPath['A.typ']!.fileRefs, ['manual-pdf']);
    expect(index.backlinksByTarget['B.typ'], ['A.typ']);
  });

  test('bad Typst text does not crash scanner', () {
    final note = scanNote('Bad.typ', '#note(title: "Bad"');
    expect(note.title, 'Bad');
    expect(note.outgoingLinks, isEmpty);
  });

  test('link resolver prefers id then alias then title then filename stem', () {
    final index = VaultIndex(
      notesByPath: {
        'pages/Real.typ': const NoteRef(
          id: 'real-id',
          path: 'pages/Real.typ',
          title: 'Display',
          aliases: ['alias-real'],
          outgoingLinks: [],
        ),
        'pages/Stem.typ': const NoteRef(
          id: 'stem-id',
          path: 'pages/Stem.typ',
          title: 'Other',
          outgoingLinks: [],
        ),
      },
      backlinksByTarget: const {},
    );

    expect(resolveLinkPath(index, 'real-id'), 'pages/Real.typ');
    expect(resolveLinkPath(index, 'alias-real'), 'pages/Real.typ');
    expect(resolveLinkPath(index, 'Display'), 'pages/Real.typ');
    expect(resolveLinkPath(index, 'Stem'), 'pages/Stem.typ');
    expect(resolveLinkPath(index, 'Missing'), isNull);
  });

  test('link resolver marks ambiguous titles', () {
    final index = VaultIndex(
      notesByPath: {
        'pages/A.typ': const NoteRef(
          id: 'a',
          path: 'pages/A.typ',
          title: 'Same',
          outgoingLinks: [],
        ),
        'pages/B.typ': const NoteRef(
          id: 'b',
          path: 'pages/B.typ',
          title: 'Same',
          outgoingLinks: [],
        ),
      },
      backlinksByTarget: const {},
    );

    final result = resolveLink(index, 'Same');
    expect(result.status, LinkResolutionStatus.ambiguous);
    expect(resolveLinkPath(index, 'Same'), isNull);
  });
}
