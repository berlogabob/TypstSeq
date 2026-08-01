import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/models.dart';
import 'package:tylog/scanner.dart';
import 'package:tylog/vault_storage.dart';

void main() {
  test(
    'v5 scanner extracts Typst metadata, backlinks, dates, files, and tasks',
    () async {
      final dir = await Directory.systemTemp.createTemp('tylog_scanner_');
      addTearDown(() => dir.delete(recursive: true));
      await Directory('${dir.path}/notes').create(recursive: true);
      await File('${dir.path}/notes/A.typ').writeAsString(
        '''#import "/_system/tylog.typ" as tylog
#show: tylog.note.with(
  id: "a-id",
  title: "A",
  kind: "note",
  project: "research",
  tags: ("journal", "pkms",),
  aliases: ("alpha",),
)

#tylog.ref-note("b-id")[B]
#tylog.tag("work")
#tylog.date-ref("2026-07-13")[Delivery]
#tylog.attachment("assets/manual.pdf")[Manual]
#tylog.attachment("assets/image.png", kind: "image")[Image]
#tylog.task(id: "task-1", text: "Write", due: "2026-07-13")
''',
      );
      await File('${dir.path}/notes/B.typ').writeAsString(
        '''#import "/_system/tylog.typ" as tylog
#show: tylog.note.with(id: "b-id", title: "B", kind: "note")
= B
''',
      );

      final index = await scanVaultStorage(LocalVaultStorage(dir));
      final note = index.notesByPath['notes/A.typ']!;

      expect(note.id, 'a-id');
      expect(note.kind, 'note');
      expect(note.project, 'research');
      expect(note.tags, ['journal', 'pkms', 'work']);
      expect(note.aliases, ['alpha']);
      expect(note.outgoingLinks, ['b-id']);
      expect(note.dateRefs.single.date, '2026-07-13');
      expect(
        note.attachments.map((item) => item.path),
        containsAll(['assets/manual.pdf', 'assets/image.png']),
      );
      expect(index.backlinksByTarget['notes/B.typ'], ['notes/A.typ']);
      expect(index.tasks.single.id, 'task-1');
      expect(index.calendar.map((item) => item.date), contains('2026-07-13'));
    },
  );

  test('bad Typst text does not crash fallback scanner', () {
    final note = scanNote(
      'notes/Bad.typ',
      '#show: tylog.note.with(id: "bad", title: "Bad"',
    );
    expect(note.title, 'Bad');
    expect(note.outgoingLinks, isEmpty);
  });

  test('broken Typst body does not block backlinks', () async {
    final dir = await Directory.systemTemp.createTemp('tylog_broken_');
    addTearDown(() => dir.delete(recursive: true));
    await Directory('${dir.path}/notes').create(recursive: true);
    await File('${dir.path}/notes/A.typ').writeAsString(
      '''#show: tylog.note.with(id: "a", title: "A")
#tylog.ref-note("b")[B]
#does-not-exist()
''',
    );
    await File(
      '${dir.path}/notes/B.typ',
    ).writeAsString('#show: tylog.note.with(id: "b", title: "B")');

    final index = await scanVaultStorage(LocalVaultStorage(dir), force: true);
    expect(index.backlinksByTarget['notes/B.typ'], ['notes/A.typ']);
  });

  test('legacy source:: URLs are not registered as note links', () async {
    final dir = await Directory.systemTemp.createTemp('tylog_srclink_');
    addTearDown(() => dir.delete(recursive: true));
    await Directory('${dir.path}/articles').create(recursive: true);
    await File('${dir.path}/articles/Auto.typ').writeAsString(
      '''#show: tylog.note.with(id: "auto", title: "Auto", kind: "article")
source:: #link("https://medium.com/")[medium.com]
''',
    );
    await File('${dir.path}/articles/Bare.typ').writeAsString(
      '''#show: tylog.note.with(id: "bare", title: "Bare", kind: "article")
source:: https://example.com/page
''',
    );
    await File('${dir.path}/articles/Wiki.typ').writeAsString(
      '''#show: tylog.note.with(id: "wiki", title: "Wiki", kind: "article")
source:: [[real-id]]
''',
    );
    await File('${dir.path}/articles/Real.typ').writeAsString(
      '#show: tylog.note.with(id: "real-id", title: "Real")',
    );

    final index = await scanVaultStorage(LocalVaultStorage(dir));

    expect(index.notesByPath['articles/Auto.typ']!.outgoingLinks, isEmpty);
    expect(index.notesByPath['articles/Bare.typ']!.outgoingLinks, isEmpty);
    // A real [[wiki]] source is still recovered and resolved.
    expect(index.notesByPath['articles/Wiki.typ']!.outgoingLinks, ['real-id']);
    expect(index.backlinksByTarget['articles/Real.typ'], ['articles/Wiki.typ']);
    expect(index.problems.where((p) => p.code == 'broken-link'), isEmpty);
  });

  test('cached URL outgoing links do not produce broken-link problems', () async {
    final dir = await Directory.systemTemp.createTemp('tylog_srccache_');
    addTearDown(() => dir.delete(recursive: true));
    await Directory('${dir.path}/articles').create(recursive: true);
    await File('${dir.path}/articles/A.typ').writeAsString(
      '#show: tylog.note.with(id: "a", title: "A", kind: "article")',
    );

    final first = await scanVaultStorage(LocalVaultStorage(dir));
    // Simulate a cache written by the pre-fix scanner, which recorded the
    // raw source:: URL as an outgoing link on the cached note.
    final poisoned = VaultIndex(
      notesByPath: {
        'articles/A.typ': first.notesByPath['articles/A.typ']!.copyWith(
          outgoingLinks: ['#link("https://medium.com/")[medium.com]'],
        ),
      },
      backlinksByTarget: const {},
    );

    final second = await scanVaultStorage(
      LocalVaultStorage(dir),
      previous: poisoned,
    );
    expect(second.problems.where((p) => p.code == 'broken-link'), isEmpty);
  });

  test('link resolver prefers id, alias, title, then filename stem', () {
    final index = VaultIndex(
      notesByPath: {
        'notes/Real.typ': const NoteRef(
          id: 'real-id',
          path: 'notes/Real.typ',
          title: 'Display',
          aliases: ['alias-real'],
          outgoingLinks: [],
        ),
        'notes/Stem.typ': const NoteRef(
          id: 'stem-id',
          path: 'notes/Stem.typ',
          title: 'Other',
          outgoingLinks: [],
        ),
      },
      backlinksByTarget: const {},
    );

    expect(resolveLinkPath(index, 'real-id'), 'notes/Real.typ');
    expect(resolveLinkPath(index, 'alias-real'), 'notes/Real.typ');
    expect(resolveLinkPath(index, 'Display'), 'notes/Real.typ');
    expect(resolveLinkPath(index, 'Stem'), 'notes/Stem.typ');
    expect(resolveLinkPath(index, 'Missing'), isNull);
  });

  test('link resolver marks ambiguous titles', () {
    final result = resolveLink(
      const VaultIndex(
        notesByPath: {
          'notes/A.typ': NoteRef(
            id: 'a',
            path: 'notes/A.typ',
            title: 'Same',
            outgoingLinks: [],
          ),
          'notes/B.typ': NoteRef(
            id: 'b',
            path: 'notes/B.typ',
            title: 'Same',
            outgoingLinks: [],
          ),
        },
        backlinksByTarget: {},
      ),
      'Same',
    );
    expect(result.status, LinkResolutionStatus.ambiguous);
  });

  test('balanced locator ignores comments, strings, and raw blocks', () {
    final calls = locateTypstCalls(r'''
// #tylog.tag("ignored")
/* #tylog.ref-note("ignored")[Ignored] */
`#tylog.attachment("ignored")`
Text "#tylog.tag(\"ignored\")"
#tylog.ref-note("real")[Real] #tylog.attachment("assets/a.pdf")[PDF]
''');
    expect(calls.map((call) => call.name), [
      'tylog.ref-note',
      'tylog.attachment',
    ]);
    expect(calls.first.source, endsWith('[Real]'));
  });

  test('managed header rewrite preserves body byte-for-byte', () {
    const body = '\n\n= Original\n\nKeep all body bytes.\n';
    final original =
        '#import "/_system/tylog.typ" as tylog\n\n'
        '#show: tylog.note.with(id: "old", title: "Old")$body';
    final updated = replaceNoteHeader(
      original,
      const NoteMetadataDraft(
        id: 'old',
        title: 'New "title"',
        kind: 'project',
        tags: ['pkms'],
      ),
    );

    expect(updated, endsWith(body));
    expect(updated, contains(r'title: "New \"title\""'));
    expect(scanNote('projects/A.typ', updated).kind, 'project');
  });

  test('Typst query decoder extracts metadata values', () {
    final values = decodeTypstMetadata(
      '[{"func":"metadata","value":{"id":"n1"},"label":"<note>"}]',
    );
    expect((values.single as Map)['id'], 'n1');
  });

  test('Format v1 envelopes retain the six stable metadata labels', () {
    const queried = '''[
      {"func":"metadata","value":{"schema":1,"entity":"note","id":"n1"},"label":"<tylog-note>"},
      {"func":"metadata","value":{"schema":1,"entity":"link","target":"n2"},"label":"<tylog-link>"},
      {"func":"metadata","value":{"schema":1,"entity":"tag","name":"format"},"label":"<tylog-tag>"},
      {"func":"metadata","value":{"schema":1,"entity":"date","date":"2026-07-14"},"label":"<tylog-date>"},
      {"func":"metadata","value":{"schema":1,"entity":"attachment","path":"assets/spec.pdf"},"label":"<tylog-attachment>"},
      {"func":"metadata","value":{"schema":1,"entity":"task","id":"t1","text":"Test"},"label":"<tylog-task>"}
    ]''';

    final values = decodeTypstMetadata(queried).cast<Map>();
    expect(values.map((value) => value['schema']), everyElement(1));
    expect(values.map((value) => value['entity']), [
      'note',
      'link',
      'tag',
      'date',
      'attachment',
      'task',
    ]);
  });

  test('scanner derives native Typst citations outside comments and strings', () {
    final note = scanNote(
      'notes/A.typ',
      '#show: tylog.note.with(id: "a", title: "A")\nText @real // @comment\n"@string" and @second-key.',
    );
    expect(note.citations, ['real', 'second-key']);
  });

  test('escaped entity mentions are not indexed as citations', () {
    final note = scanNote(
      'notes/A.typ',
      r'#show: tylog.note.with(id: "a", title: "A")'
          '\n'
          r'#tylog.ref-note("fernando")[\@Fernando] and @real.',
    );
    expect(note.citations, ['real']);
  });

  test('10k note resolver remains linear-time', () {
    final notes = List.generate(
      10000,
      (i) => NoteRef(
        id: 'n$i',
        path: 'notes/n$i.typ',
        title: 'Note $i',
        outgoingLinks: const [],
      ),
    );
    final stopwatch = Stopwatch()..start();
    final resolver = LinkResolver(notes);
    for (var i = 0; i < notes.length; i++) {
      expect(resolver.resolve('n$i').path, 'notes/n$i.typ');
    }
    stopwatch.stop();
    expect(stopwatch.elapsed, lessThan(const Duration(seconds: 2)));
  });

  test('forced rebuild can be cancelled without a partial index', () async {
    final dir = await Directory.systemTemp.createTemp('tylog_cancel_');
    addTearDown(() => dir.delete(recursive: true));
    await Directory('${dir.path}/notes').create(recursive: true);
    await File(
      '${dir.path}/notes/a.typ',
    ).writeAsString('#show: tylog.note.with(id: "a", title: "A")');
    await expectLater(
      scanVaultStorage(
        LocalVaultStorage(dir),
        force: true,
        isCancelled: () => true,
      ),
      throwsA(isA<IndexBuildCancelled>()),
    );
  });
}
