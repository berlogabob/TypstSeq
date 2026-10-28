import 'dart:io';

import 'package:test/test.dart';
import 'package:tylog_core/tylog_core.dart';

NoteRef entity(
  String id,
  String title, {
  String kind = 'person',
  List<String> aliases = const [],
}) => NoteRef(
  id: id,
  path: 'notes/$id.typ',
  title: title,
  kind: kind,
  aliases: aliases,
  outgoingLinks: const [],
);

NoteRef day(
  String date, {
  List<String> links = const [],
  List<String> tags = const [],
}) => NoteRef(
  id: date,
  path: 'daily/${date.substring(0, 4)}/${date.substring(5, 7)}/$date.typ',
  title: date,
  kind: 'daily',
  tags: tags,
  outgoingLinks: links,
);

VaultIndex indexOf(List<NoteRef> notes) => VaultIndex(
  notesByPath: {for (final note in notes) note.path: note},
  backlinksByTarget: const {},
);

EnrichMentions mentionsOf(
  List<EnrichMention> mentions, {
  List<String> keywords = const [],
}) => EnrichMentions(
  note: 'x',
  contentSha: 'x',
  mentions: mentions,
  keywords: keywords,
);

void main() {
  final silva = entity('andre-silva', 'André Silva');
  final costa = entity('andre-costa', 'André Costa');
  final iade = entity('iade', 'IADE', kind: 'organization');
  final band = entity('band', 'Sounding Doubts', kind: 'project');
  // History: Silva shows up with IADE, Costa with the band.
  final history = [
    for (var i = 1; i <= 5; i++)
      day('2026-09-0$i', links: ['andre-silva', 'iade']),
    for (var i = 1; i <= 5; i++)
      day('2026-08-0$i', links: ['andre-costa', 'band']),
  ];
  final index = indexOf([silva, costa, iade, band, ...history]);
  const andre = EnrichMention(surface: 'André', type: 'person', line: 3);
  const iadeMention = EnrichMention(
    surface: 'IADE',
    type: 'organization',
    line: 3,
  );

  test('first name alone is ambiguous: review, not link', () {
    final [decision] = resolveMentions(
      mentionsOf([andre]),
      day('2026-10-01'),
      EnrichMemory.build(index),
    );
    expect(decision.status, EnrichStatus.review);
    expect(
      decision.candidates.map((c) => c.note.id),
      unorderedEquals(['andre-silva', 'andre-costa']),
    );
  });

  test('context picks the right André, and an accept makes it a link', () {
    final mentions = mentionsOf([andre, iadeMention]);
    final memory = EnrichMemory.build(index);
    final [first, org] = resolveMentions(mentions, day('2026-10-01'), memory);
    expect(org.status, EnrichStatus.linked);
    expect(first.target!.id, 'andre-silva');
    expect(
      first.candidates[0].score,
      greaterThan(first.candidates[1].score + 1),
    );
    // Ranked first, but a prefix-only name still asks the user once.
    expect(first.status, EnrichStatus.review);
    final learned = EnrichMemory.build(index, [
      const EnrichFeedback(
        surface: 'André',
        entity: 'andre-silva',
        accepted: true,
        note: 'd',
        at: 't',
      ),
    ]);
    final [again, _] = resolveMentions(mentions, day('2026-10-02'), learned);
    expect(again.status, EnrichStatus.linked);
    expect(again.target!.id, 'andre-silva');
  });

  test('with the band in the note the same surface means Costa', () {
    final learned = EnrichMemory.build(index, [
      const EnrichFeedback(
        surface: 'André',
        entity: 'andre-silva',
        accepted: true,
        note: 'd',
        at: 't',
      ),
      const EnrichFeedback(
        surface: 'André',
        entity: 'andre-costa',
        accepted: true,
        note: 'd',
        at: 't',
      ),
    ]);
    const bandMention = EnrichMention(
      surface: 'Sounding Doubts',
      type: 'project',
      line: 4,
    );
    final [decision, _] = resolveMentions(
      mentionsOf([andre, bandMention]),
      day('2026-10-03'),
      learned,
    );
    expect(decision.target!.id, 'andre-costa');
    expect(decision.status, EnrichStatus.linked);
  });

  test('a rejected pair is never suggested again', () {
    final memory = EnrichMemory.build(index, [
      const EnrichFeedback(
        surface: 'andre',
        entity: 'andre-costa',
        accepted: false,
        note: 'd',
        at: 't',
      ),
    ]);
    final [decision] = resolveMentions(
      mentionsOf([andre]),
      day('2026-10-01'),
      memory,
    );
    expect(decision.candidates.map((c) => c.note.id), ['andre-silva']);
    expect(
      decision.status,
      EnrichStatus.review,
    ); // prefix only, not yet accepted
  });

  test(
    'hints and aliases find a nickname; the model id is only a fallback',
    () {
      final katia = entity('kz', 'katiazhavoronkova', aliases: ['жаворонкова']);
      final barbara = entity('barbara', 'Barbara');
      final memory = EnrichMemory.build(indexOf([katia, barbara]));
      final decisions = resolveMentions(
        mentionsOf(const [
          EnrichMention(
            surface: 'Катя',
            type: 'person',
            line: 1,
            hints: ['Katia'],
          ),
          // Wrong id from the model, as seen on the real vault: the name wins.
          EnrichMention(
            surface: 'Barbara',
            type: 'person',
            line: 1,
            entity: 'kz',
          ),
          EnrichMention(surface: 'Рома', type: 'person', line: 1),
          EnrichMention(surface: 'граф', type: 'topic', line: 1),
        ]),
        day('2026-10-22'),
        memory,
      );
      expect(
        decisions.map((d) => (d.mention.surface, d.status, d.target?.id)),
        [
          ('Катя', EnrichStatus.review, 'kz'),
          ('Barbara', EnrichStatus.linked, 'barbara'),
          ('Рома', EnrichStatus.propose, null),
        ],
      );
    },
  );

  test('a hint that names a known alias finds her but does not prove it', () {
    // Real vault: the model hinted "Катя" with the alias of a known person.
    final katia = entity('kz', 'katiazhavoronkova', aliases: ['жаворонкова']);
    final [decision] = resolveMentions(
      mentionsOf(const [
        EnrichMention(
          surface: 'Катя',
          type: 'person',
          line: 1,
          hints: ['Жаворонкова'],
        ),
      ]),
      day('2026-10-22'),
      EnrichMemory.build(indexOf([katia])),
    );
    expect((decision.status, decision.target?.id), (EnrichStatus.review, 'kz'));
  });

  test('case forms of one new name make one proposal', () {
    final decisions = resolveMentions(
      mentionsOf(const [
        EnrichMention(
          surface: 'Ромой',
          type: 'person',
          line: 1,
          hints: ['Роман'],
        ),
        EnrichMention(
          surface: 'Рома',
          type: 'person',
          line: 2,
          hints: ['Роман'],
        ),
        EnrichMention(
          surface: 'Настей',
          type: 'person',
          line: 2,
          hints: ['Настя'],
        ),
      ]),
      day('2026-10-21'),
      EnrichMemory.build(indexOf(const [])),
    );
    expect(decisions.map((d) => d.mention.surface), ['Ромой', 'Настей']);
  });

  test('only existing tags are added, and a removed tag stays removed', () {
    final tagged = indexOf([
      day('2026-10-01', tags: ['design', 'journal']),
    ]);
    expect(enrichTags(['Design', 'новое', 'journal'], tagged), ['design']);
    final memory = EnrichMemory.build(tagged, [
      EnrichFeedback(
        surface: 'design',
        entity: enrichTagEntity('design'),
        accepted: false,
        note: 'd',
        at: 't',
      ),
    ]);
    expect(enrichTags(['design'], tagged, memory: memory), isEmpty);
  });

  test('ledger parsing skips bad lines', () {
    final events = EnrichFeedback.parseLedger(
      '{"decision":"accept","surface":"A","entity":"a"}\nnot json\n'
      '{"decision":"reject","surface":"B","entity":"b"}\n',
    );
    expect(events.map((e) => (e.entity, e.accepted)), [
      ('a', true),
      ('b', false),
    ]);
  });

  test('content sha matches the Python worker', () {
    // Same bytes as tool/test_enrich_worker.py would hash: block stripped.
    const body = '= Day\n\nhello\n';
    expect(
      enrichContentSha('$body\n$autoEntitiesMarker\n== Mentions\n'),
      enrichContentSha(body),
    );
    // Computed with tool/enrich_worker.py content_sha().
    expect(
      enrichContentSha('$body\n$autoEntitiesMarker\n== Mentions\n'),
      '344c6bcf6be749a8070f7a41f49390ca2828ede86ff97ae448c35647905912ca',
    );
    expect(enrichContentSha(body), isNot(enrichContentSha('$body!')));
  });

  test('writing the block is not an edit, even after trailing blanks', () {
    // Real vault: a day ending in "в точку . " plus blank lines lost its
    // trailing blanks to the block, and every device then saw an edit.
    const body = '= Day\n\nв точку . \n\n\n';
    final note = day('2026-10-22');
    final linked = EnrichDecision(
      const EnrichMention(surface: 'IADE', type: 'organization', line: 3),
      EnrichStatus.linked,
      [
        EnrichCandidate(
          entity('iade', 'IADE', kind: 'organization'),
          0,
          strong: true,
        ),
      ],
    );
    final written = writeAutoEntities(body, note, [linked], const []);
    expect(written, contains(autoEntitiesMarker));
    expect(enrichContentSha(written), enrichContentSha(body));
    // Computed with tool/enrich_worker.py content_sha().
    expect(
      enrichContentSha(body),
      '98e4ab71821ed482817f51df3f49becd38aea18e74b37327571cc5b29397e91a',
    );
  });

  test('a name linked on its line is settled', () {
    const roma = EnrichMention(surface: 'Рома', type: 'person', line: 2);
    expect(enrichLinkedOnLine(roma, ['x', 'с Ромой и Рома']), isFalse);
    expect(
      enrichLinkedOnLine(roma, ['x', 'с #tylog.ref-note("new")[Рома] тут']),
      isTrue,
    );
    expect(enrichLinkedOnLine(roma, ['x']), isFalse);
  });

  group('markers', () {
    final fixit = entity('fx', 'fixit', kind: 'note');
    const day20 =
        '= 2026-10-20\n\n'
        '\\- 13:34 решаем проблему поиска\n'
        '+ поиск не работает корректно\n'
        '#tylog.ref-note("fixit")[fixit] уже помечено\n';
    final markerIndex = indexOf([fixit]);
    final found = EnrichMentions(
      note: 'd',
      contentSha: 'x',
      markers: const [
        (3, 'fx'),
        (4, 'fx'),
        (5, 'fx'),
        (99, 'fx'),
        (4, 'Купить'),
      ],
    );

    test('offers unmarked, existing, not rejected lines', () {
      final offers = enrichMarkerOffers(
        found,
        day20,
        markerIndex,
        EnrichMemory.build(markerIndex, [
          EnrichFeedback(
            surface: 'решаем проблему поиска',
            entity: enrichMarkerEntity('fx'),
            accepted: false,
            note: 'd',
            at: 't',
          ),
        ]),
      );
      expect(offers.map((o) => (o.line, o.marker.id, o.text)), [
        (4, 'fx', 'поиск не работает корректно'),
        (4, 'Купить', 'поиск не работает корректно'),
      ]);
      expect(
        markLine(day20, 4, offers.last.marker).split('\n')[3],
        '+ #tylog.ref-note("Купить")[Купить] поиск не работает корректно',
      );
    });

    test('a typed marker word becomes the link instead of doubling', () {
      const source = '- 23:08 Fixit: нет очереди\n- fixity of the theory';
      final marked = markLine(source, 1, fixit).split('\n');
      expect(marked[0], '- 23:08 #tylog.ref-note("fx")[fixit]: нет очереди');
      expect(
        markLine(source, 2, fixit).split('\n')[1],
        '- #tylog.ref-note("fx")[fixit] fixity of the theory',
      );
    });

    test('marking puts the link after list marker and time, once', () {
      final once = markLine(day20, 3, fixit);
      expect(
        once.split('\n')[2],
        r'\- 13:34 #tylog.ref-note("fx")[fixit] решаем проблему поиска',
      );
      expect(markLine(once, 3, fixit), once);
      expect(
        markLine(day20, 4, fixit).split('\n')[3],
        '+ #tylog.ref-note("fx")[fixit] поиск не работает корректно',
      );
      expect(markLine(day20, 5, fixit), day20); // marked by title already
      expect(
        enrichPlainLine(r'\- 21:50 #tylog.ref-note("fx")[fixit] text'),
        'fixit text',
      );
    });

    test('marked lines compile', () {
      if (Process.runSync('which', ['typst']).exitCode != 0) {
        markTestSkipped('typst not on PATH');
        return;
      }
      final root = Directory.current.path.endsWith('packages/tylog_core')
          ? Directory.current.parent.parent.path
          : Directory.current.path;
      final dir = Directory('$root/.dart_tool/tylog_marker_test')
        ..createSync(recursive: true);
      addTearDown(() => dir.deleteSync(recursive: true));
      final source =
          '#import "/typst/tylog/lib.typ" as tylog\n${markLine(markLine(day20, 3, fixit), 4, fixit)}';
      final file = File('${dir.path}/m.typ')..writeAsStringSync(source);
      final result = Process.runSync('typst', [
        'compile',
        '--root',
        root,
        file.path,
        '${file.path}.pdf',
      ]);
      expect(result.exitCode, 0, reason: '${result.stderr}\n$source');
    });
  });

  group('writing', () {
    const header =
        '#import "/_system/tylog.typ" as tylog\n\n'
        '#show: tylog.note.with(id: "2026-10-01", title: "2026-10-01", kind: "daily")\n\n'
        '= 2026-10-01\n\nmet André at IADE\n';
    final note = day('2026-10-01', tags: ['journal']);
    final linked = EnrichDecision(iadeMention, EnrichStatus.linked, [
      EnrichCandidate(iade, 0, strong: true),
    ]);

    test('block is idempotent and keeps text typed after it', () {
      final once = writeAutoEntities(header, note, [linked], ['design']);
      expect(once, contains('- #tylog.ref-note("iade")[IADE]'));
      expect(once, contains('#tylog.tag("design")'));
      expect(writeAutoEntities(once, note, [linked], ['design']), once);
      final typedAfter = '$once\nlater thought\n';
      final rewritten = writeAutoEntities(typedAfter, note, const [], const []);
      expect(rewritten, contains('later thought'));
      expect(rewritten, isNot(contains(autoEntitiesMarker)));
      expect(stripAutoEntities(once), header);
      // Once indexed, the note carries the block's own link and tag; the
      // next pass must still write the same block (no add/drop flip-flop).
      final indexed = scanNote(note.path, once);
      expect(indexed.outgoingLinks, contains('iade'));
      expect(writeAutoEntities(once, indexed, [linked], ['design']), once);
    });

    test('already linked inline: no duplicate in the block', () {
      final inline = header.replaceFirst(
        'at IADE',
        'at #tylog.ref-note("iade")[IADE]',
      );
      expect(writeAutoEntities(inline, note, [linked], const []), inline);
    });

    test('inline link edits only that mention and skips existing markup', () {
      const mention = EnrichMention(surface: 'André', type: 'person', line: 7);
      final out = linkMentionInline(header, mention, silva);
      expect(
        out.split('\n')[6],
        'met #tylog.ref-note("andre-silva")[André] at IADE',
      );
      expect(linkMentionInline(out, mention, silva), out);
      expect(
        linkMentionInline(
          header,
          const EnrichMention(surface: 'Zed', type: 'person', line: 7),
          silva,
        ),
        header,
      );
    });

    test('output compiles', () {
      if (Process.runSync('which', ['typst']).exitCode != 0) {
        markTestSkipped('typst not on PATH');
        return;
      }
      final root = Directory.current.path.endsWith('packages/tylog_core')
          ? Directory.current.parent.parent.path
          : Directory.current.path;
      final dir = Directory('$root/.dart_tool/tylog_enrich_test')
        ..createSync(recursive: true);
      addTearDown(() => dir.deleteSync(recursive: true));
      const mention = EnrichMention(surface: 'André', type: 'person', line: 7);
      final source = writeAutoEntities(
        linkMentionInline(header, mention, silva),
        note,
        [linked],
        ['design'],
      ).replaceFirst('/_system/tylog.typ', '/typst/tylog/lib.typ');
      final file = File('${dir.path}/day.typ')..writeAsStringSync(source);
      final result = Process.runSync('typst', [
        'compile',
        '--root',
        root,
        file.path,
        '${file.path}.pdf',
      ]);
      expect(result.exitCode, 0, reason: '${result.stderr}\n$source');
    });
  });
}
