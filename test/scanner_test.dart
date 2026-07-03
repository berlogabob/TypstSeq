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

  test('balanced locator ignores comments and strings', () {
    final calls = locateTypstCalls(r'''
// #wikilink("ignored")
/* #tag("ignored") */
`#filelink("ignored")`
#note(id: "real", title: "A (quoted)", tags: ("x",))
Text "#wikilink(\"ignored\")" #wikilink("real") #filelink("pdf")
''');

    expect(calls.map((call) => call.name), ['note', 'wikilink', 'filelink']);
    expect(calls.first.source, contains('A (quoted)'));
  });

  test('managed header rewrite preserves body byte-for-byte', () {
    const body = '\n\n= Original\n\nKeep (all) body bytes.\n';
    final original =
        '#import "/.tylog/tylog.typ": *\n\n'
        '#note(id: "old", title: "Old")$body';
    final updated = replaceNoteHeader(
      original,
      const NoteMetadataDraft(
        id: 'old',
        title: 'New "title"',
        tags: ['pkms'],
        links: ['next'],
      ),
    );

    expect(updated, endsWith(body));
    expect(updated, contains(r'title: "New \"title\""'));
    expect(scanNote('A.typ', updated).tags, ['pkms']);
  });

  test('Typst query decoder extracts metadata values', () {
    final values = decodeTypstMetadata(
      '[{"func":"metadata","value":{"id":"n1"},"label":"<note>"}]',
    );
    expect((values.single as Map)['id'], 'n1');
  });

  test(
    'scanner derives native Typst citations outside comments and strings',
    () {
      final note = scanNote(
        'A.typ',
        'Text @real // @comment\n"@string" and @second-key.',
      );
      expect(note.citations, ['real', 'second-key']);
    },
  );

  test('10k note resolver remains linear-time', () {
    final notes = List.generate(
      10000,
      (i) => NoteRef(
        id: 'n$i',
        path: 'pages/n$i.typ',
        title: 'Note $i',
        outgoingLinks: const [],
      ),
    );
    final stopwatch = Stopwatch()..start();
    final resolver = LinkResolver(notes);
    for (var i = 0; i < notes.length; i++) {
      expect(resolver.resolve('n$i').path, 'pages/n$i.typ');
    }
    stopwatch.stop();

    expect(stopwatch.elapsed, lessThan(const Duration(seconds: 2)));
  });

  test(
    'forced rebuild can be cancelled without returning a partial index',
    () async {
      final dir = await Directory.systemTemp.createTemp('tylog_cancel_');
      addTearDown(() => dir.delete(recursive: true));
      await File(
        '${dir.path}/a.typ',
      ).writeAsString('#note(id: "a", title: "A")');

      await expectLater(
        scanVault(dir, force: true, isCancelled: () => true),
        throwsA(isA<IndexBuildCancelled>()),
      );
    },
  );
}
