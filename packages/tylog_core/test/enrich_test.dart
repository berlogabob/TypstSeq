import 'dart:convert';
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
  group('learned person nicknames', () {
    final person = entity('zak', 'Андрей Олегович Закатаны');
    final purchase = entity(
      'purchase',
      'Закупка на 2019 для Ивана',
      kind: 'note',
    );
    final index = indexOf([person, purchase]);
    EnrichDecision resolve(String surface, EnrichMemory memory) =>
        resolveMentions(
          mentionsOf([
            EnrichMention(surface: surface, type: 'person', line: 1),
          ]),
          day('2026-11-04'),
          memory,
        ).single;
    const forms = ['Зак', 'Зака', 'Заку', 'Заком', 'Заке'];
    const accept = EnrichFeedback(
      surface: 'Заку',
      entity: 'zak',
      accepted: true,
      note: 'd',
      at: 't',
    );

    test('an unknown nickname proposes a person', () {
      final result = resolve('Заку', EnrichMemory.build(index));
      expect(result.status, EnrichStatus.propose);
      expect(result.candidates, isEmpty);
    });
    test('a manual alias matches the case forms', () {
      final memory = EnrichMemory.build(
        indexOf([
          entity('zak', person.title, aliases: ['Зак']),
          purchase,
        ]),
      );
      for (final form in forms) {
        expect(resolve(form, memory).target?.id, 'zak', reason: form);
      }
      expect(resolve('Закон', memory).target, isNull);
      expect(resolve('Закупка', memory).target?.id, isNot('zak'));
    });
    test('an accepted ledger choice matches case forms', () {
      final memory = EnrichMemory.build(
        index,
        EnrichFeedback.parseLedger(
          '{"decision":"accept","surface":"Заку","entity":"zak"}',
        ),
      );
      for (final form in forms) {
        expect(resolve(form, memory).target?.id, 'zak', reason: form);
      }
      expect(resolve('Закон', memory).target, isNull);
      expect(resolve('Закупка', memory).target?.id, isNot('zak'));
    });
    test('a rejection suppresses other case forms', () {
      final memory = EnrichMemory.build(index, [
        accept,
        const EnrichFeedback(
          surface: 'Зака',
          entity: 'zak',
          accepted: false,
          note: 'd',
          at: 't',
        ),
      ]);
      for (final form in forms) {
        expect(
          resolve(form, memory).candidates.map((c) => c.note.id),
          isNot(contains('zak')),
          reason: form,
        );
      }
    });
  });
  test('Russian name endings match but arbitrary suffixes do not', () {
    final memory = EnrichMemory.build(indexOf([entity('andrey', 'Андрей')]));
    EnrichDecision resolve(String surface) => resolveMentions(
      mentionsOf([EnrichMention(surface: surface, type: 'person', line: 1)]),
      day('2026-11-04'),
      memory,
    ).single;
    for (final form in ['Андрея', 'Андрею', 'Андреем', 'Андрее', 'Андрей']) {
      expect(resolve(form).target?.id, 'andrey', reason: form);
    }
    expect(resolve('Андрейб').target, isNull);
  });

  test('day resolution discards a sidecar surface inside a word', () {
    final person = entity('andrey', 'Андрей');
    final note = day('2026-11-04');
    final index = indexOf([person, note]);
    final result = resolveEnrichDay(
      mentionsOf([
        const EnrichMention(surface: 'Андрей', type: 'person', line: 1),
      ]),
      note,
      EnrichMemory.build(index),
      index,
      '14:27 Андрейб соберись',
    );
    expect(result.decisions, isEmpty);
  });

  test('Angelas matches Angela through the existing Latin suffix rule', () {
    final memory = EnrichMemory.build(indexOf([entity('angela', 'Angela')]));
    final decision = resolveMentions(
      mentionsOf([
        const EnrichMention(surface: 'Angelas', type: 'person', line: 1),
      ]),
      day('2026-11-04'),
      memory,
    ).single;
    expect(decision.target?.id, 'angela');
  });

  test(
    'day resolution filters typed links and returns matching tags/markers',
    () {
      final person = entity('person', 'Alex');
      final marker = entity('fixit', 'fixit', kind: 'note');
      final note = day('2026-11-04');
      final tagged = NoteRef(
        id: 'tagged',
        path: 'notes/tagged.typ',
        title: 'Tagged',
        tags: const ['design'],
        outgoingLinks: const [],
      );
      final index = indexOf([person, marker, note, tagged]);
      final memory = EnrichMemory.build(index);
      const source =
          '#import "/_system/tylog.typ" as tylog\n'
          '#show: tylog.note.with(id: "2026-11-04", title: "2026-11-04", kind: "daily")\n'
          '- #tylog.ref-note("person")[Alex] met Alex\n'
          '- fix the build\n';
      final mentions = EnrichMentions(
        note: note.path,
        contentSha: 'unused',
        mentions: const [
          EnrichMention(surface: 'Alex', type: 'person', line: 2),
        ],
        keywords: const ['Design'],
        markers: const [(4, 'fixit')],
      );

      final result = resolveEnrichDay(mentions, note, memory, index, source);

      expect(result.decisions, isEmpty);
      expect(result.tags, ['design']);
      expect(result.markers.single.text, 'fix the build');
    },
  );

  test('repeated unrelated mentions do not scan the whole vault', () {
    final memory = EnrichMemory.build(
      indexOf([for (var i = 0; i < 10000; i++) entity('id$i', 'Person$i')]),
    );
    final note = day('2026-11-04');
    // Warm the name cache; measure candidate lookup, not memory construction.
    resolveMentions(
      mentionsOf([
        const EnrichMention(surface: 'Nobody', type: 'person', line: 1),
      ]),
      note,
      memory,
    );
    final batch = mentionsOf([
      for (var i = 0; i < 1000; i++)
        EnrichMention(surface: 'Unmatched$i', type: 'person', line: 1),
    ]);
    final watch = Stopwatch()..start();
    final result = resolveMentions(batch, note, memory);
    expect(result, hasLength(1000));
    expect(watch.elapsedMilliseconds, lessThan(1000));
  });

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

  test('note pages, case forms and Cyrillic spelling find existing people', () {
    final nastya = entity(
      'nastya',
      'Васильченко Анастасия',
      kind: 'note',
      aliases: ['Настя'],
    );
    final pamela = entity('pamela', 'PamelaTeubig', kind: 'note');
    final rita = entity('rita', 'RitaMalaquias', kind: 'note');
    final sabino = entity('sabino', 'André Sabino', kind: 'note');
    final iadeOrg = entity('iade-org', 'IADE', kind: 'organization');
    final iadeNote = entity('iade-note', 'IADE', kind: 'note');
    final memory = EnrichMemory.build(
      indexOf([nastya, pamela, rita, sabino, iadeOrg, iadeNote]),
    );
    EnrichDecision resolve(String surface) => resolveMentions(
      mentionsOf([EnrichMention(surface: surface, type: 'person', line: 1)]),
      day('2026-11-03'),
      memory,
    ).single;
    expect(resolve('Pamela Teubig').status, EnrichStatus.linked);
    for (final form in ['Настей', 'Насте']) {
      expect(resolve(form).status, EnrichStatus.review, reason: form);
      expect(resolve(form).target?.id, 'nastya', reason: form);
    }
    expect(resolve('Рита').target?.id, 'rita');
    expect(resolve('Сабино').target?.id, 'sabino');
    expect(resolve('Маша').status, EnrichStatus.propose);
    // A stray note with the same title does not unsettle the real entity.
    expect(resolve('IADE').status, EnrichStatus.linked);
    expect(resolve('IADE').target?.id, 'iade-org');
    // A partial name sees typed and note pages alike.
    final angelaNote = entity('angela-s', 'Angela Silvestre', kind: 'note');
    final angelaPerson = entity(
      'angela-x',
      'Анжела Хавьер',
      aliases: ['Angela X'],
    );
    final both = EnrichMemory.build(indexOf([angelaNote, angelaPerson]));
    expect(
      resolveMentions(
        mentionsOf([
          const EnrichMention(surface: 'Angela', type: 'person', line: 1),
        ]),
        day('2026-11-04'),
        both,
      ).single.candidates.map((c) => c.note.id),
      unorderedEquals(['angela-s', 'angela-x']),
    );
  });

  test(
    'ignored surfaces stay hidden after ledger reload, including new names',
    () {
      final events = EnrichFeedback.parseLedger(
        '{"decision":"reject","surface":"André","entity":"mention:ignore"}\n'
        '{"decision":"reject","surface":"Unknown","entity":"mention:ignore"}',
      );
      final decisions = resolveMentions(
        mentionsOf([
          andre,
          const EnrichMention(surface: 'Unknown', type: 'person', line: 1),
        ]),
        day('2026-10-01'),
        EnrichMemory.build(index, events),
      );
      expect(decisions, isEmpty);
    },
  );

  test('feedback provenance round-trips and old ledger lines remain valid', () {
    const feedback = EnrichFeedback(
      surface: 'André',
      entity: 'andre-silva',
      accepted: true,
      note: 'daily/2026-11-06.typ',
      at: '2026-11-06T00:00:00Z',
      proposedBy: 'llm:test-model',
      confidence: 0.87,
    );
    final [roundTripped] = EnrichFeedback.parseLedger(
      '${jsonEncode(feedback)}\n',
    );
    expect(roundTripped.proposedBy, 'llm:test-model');
    expect(roundTripped.confidence, 0.87);

    final [oldLine] = EnrichFeedback.parseLedger(
      '{"decision":"accept","surface":"André","entity":"andre-silva"}',
    );
    expect(oldLine.proposedBy, isNull);
    expect(oldLine.confidence, isNull);
  });

  test('candidates show the most recent linked day', () {
    final decisions = resolveMentions(
      mentionsOf([andre]),
      day('2026-10-01'),
      EnrichMemory.build(index),
    );
    final seen = {
      for (final c in decisions.single.candidates) c.note.id: c.lastSeenDay,
    };
    expect(seen, {'andre-silva': '2026-09-05', 'andre-costa': '2026-08-05'});
  });

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

  test('shown ledger events do not change mention resolution', () {
    final mentions = mentionsOf([andre, iadeMention]);
    final note = day('2026-10-01');
    final baseline = resolveMentions(mentions, note, EnrichMemory.build(index));
    final events = EnrichFeedback.parseLedger(
      '{"decision":"shown","surface":"André","entity":"andre-silva",'
      '"note":"d","at":"t","context":["e:iade"]}\n'
      '{"decision":"shown","surface":"IADE","entity":"iade"}\n'
      '{"decision":"unknown","surface":"André","entity":"andre-costa"}',
    );
    expect(events, hasLength(2));
    expect(events.first.toJson()['decision'], 'shown');
    final actual = resolveMentions(
      mentions,
      note,
      EnrichMemory.build(index, events),
    );
    for (var i = 0; i < baseline.length; i++) {
      expect(actual[i].status, baseline[i].status);
      expect(actual[i].target?.id, baseline[i].target?.id);
      expect(
        actual[i].candidates.map((c) => (c.note.id, c.score)),
        baseline[i].candidates.map((c) => (c.note.id, c.score)),
      );
    }
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

  test('feedback can be applied to a cached memory incrementally', () {
    final memory = EnrichMemory.build(index);
    expect(memory.acceptedCount('André', 'andre-silva'), 0);
    memory.addFeedback(
      const EnrichFeedback(
        surface: 'André',
        entity: 'andre-silva',
        accepted: true,
        note: 'd',
        at: 't',
      ),
    );
    expect(memory.acceptedCount('André', 'andre-silva'), 1);
    expect(memory.isRejected('André', 'andre-silva'), isFalse);
    memory.addFeedback(
      const EnrichFeedback(
        surface: 'André',
        entity: 'andre-silva',
        accepted: false,
        note: 'd',
        at: 't2',
      ),
    );
    expect(memory.isRejected('André', 'andre-silva'), isTrue);
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

  test('a plain note whose title only starts like the name is not a match', () {
    final purchase = entity(
      'zakupka',
      'Закупка на 2019 для Ивана',
      kind: 'note',
    );
    final angela = entity(
      'angela',
      'Angela Silvestre',
      kind: 'note',
      aliases: ['Анжела'],
    );
    final andrey = entity('andrey', 'Андрей');
    final memory = EnrichMemory.build(indexOf([purchase, angela, andrey]));
    EnrichDecision resolve(String surface) => resolveMentions(
      mentionsOf([EnrichMention(surface: surface, type: 'person', line: 1)]),
      day('2026-11-04'),
      memory,
    ).single;
    expect(resolve('Заку').candidates, isEmpty);
    expect(resolve('Заку').target, isNull);
    expect(resolve('Анжела').target?.id, 'angela');
    expect(resolve('Андрея').target?.id, 'andrey');
  });

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
    // Same bytes as tool/test_enrich_worker.py would hash.
    const body = '= Day\n\nhello\n';
    expect(
      enrichContentSha('$body\n$autoEntitiesMarker\n== Mentions\n'),
      isNot(enrichContentSha(body)),
    );
    // Computed with tool/enrich_worker.py content_sha().
    expect(
      enrichContentSha('$body\n$autoEntitiesMarker\n== Mentions\n'),
      '776a9f3cf79cb6870053b24f0fe36b06c497f8ae08cda41f730f0c8b8ef6954f',
    );
    expect(enrichContentSha(body), isNot(enrichContentSha('$body!')));
  });

  test('content sha detects user text after a legacy marker', () {
    const source = '= Day\n// tylog:auto-entities\n== Mentions\n';
    expect(
      enrichContentSha(source),
      isNot(enrichContentSha('${source}new text\n')),
    );
  });

  test(
    'self-heal keeps link items, promotes tags, and preserves later text',
    () {
      const source =
          '#show: tylog.note.with(id: "d", title: "D")\n'
          '= Day\n\nBody\n\n// tylog:auto-entities\n== Mentions\n'
          '- #tylog.ref-note("alice")[Alice]\n#tylog.tag("design")\n'
          '## User heading\nKeep this\n';
      final result = selfHealAutoEntities(source);
      expect(result, contains('#tylog.ref-note("alice")[Alice]'));
      expect(result, contains('tags: ("design",)'));
      expect(result, contains('## User heading\nKeep this'));
      expect(result, isNot(contains(autoEntitiesMarker)));
      expect(selfHealAutoEntities(result), result);
    },
  );

  test('self-healed legacy block compiles', () {
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
    const legacy =
        '#import "/typst/tylog/lib.typ" as tylog\n\n'
        '#show: tylog.note.with(id: "d", title: "D")\n'
        '= Day\n// tylog:auto-entities\n== Mentions\n'
        '- #tylog.ref-note("alice")[Alice]\n#tylog.tag("design")\n';
    final file = File('${dir.path}/healed.typ')
      ..writeAsStringSync(selfHealAutoEntities(legacy));
    final result = Process.runSync('typst', [
      'compile',
      '--root',
      root,
      file.path,
      '${file.path}.pdf',
    ]);
    expect(
      result.exitCode,
      0,
      reason: '${result.stderr}\n${file.readAsStringSync()}',
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

    test('lines inside a multi-line call are never offered', () {
      const source =
          '- 09:00 купить хлеб\n'
          '#tylog.task(\n'
          '  id: "t1",\n'
          '  text: "Send notes",\n'
          ')\n'
          '- 10:00 #tylog.ref-note("x")[X] позвонить\n';
      final offers = enrichMarkerOffers(
        EnrichMentions(
          note: 'd',
          contentSha: 'x',
          markers: const [(1, 'fx'), (2, 'fx'), (4, 'fx'), (6, 'fx')],
        ),
        source,
        EnrichMemory.build(markerIndex, const []),
      );
      expect(offers.map((o) => o.line), [1, 6]);
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

    test('inline link skips URLs and partial words, links the plain word', () {
      const src =
          '= d\n\n\\- 19:23 https://www.reddit.com/r/hermesagent/comments/x/ about hermesagent\n';
      final target = entity('h', 'hermesagent');
      const mention = EnrichMention(
        surface: 'hermesagent',
        type: 'project',
        line: 3,
      );
      final out = linkMentionInline(src, mention, target);
      expect(out, contains('/r/hermesagent/comments'));
      expect(out, contains('about #tylog.ref-note("h")[hermesagent]'));
      const inWord = EnrichMention(
        surface: 'IADE',
        type: 'organization',
        line: 3,
      );
      expect(
        linkMentionInline('= d\n\nxIADEx\n', inWord, target),
        '= d\n\nxIADEx\n',
      );
    });

    test('inline link never lands inside a string or a call argument', () {
      const task =
          '= d\n\n#tylog.task(\n  id: "1",\n  text: "Angela. remind morning",\n  status: "done",\n)\n'
          '- "Angela" said\n';
      final angela = entity('angela', 'Angela Silvestre');
      for (final line in [5, 8]) {
        final mention = EnrichMention(
          surface: 'Angela',
          type: 'person',
          line: line,
        );
        expect(
          linkMentionInline(task, mention, angela),
          task,
          reason: 'line $line',
        );
      }
    });

    test('inline link never lands inside code like #tylog.task(', () {
      // 2026-11-03: "tylog" in `#tylog.task(` became
      // `##tylog.ref-note(...)[tylog].task(` and the day stopped compiling.
      const source = '= d\n\n#tylog.task(\n  id: "1",\n  text: "x",\n)\n';
      const mention = EnrichMention(surface: 'tylog', type: 'project', line: 3);
      expect(linkMentionInline(source, mention, entity('t', 'tylog')), source);
    });

    test('inline link leaves an existing link line alone (2026-11-10)', () {
      const source = '= d\n\n- #tylog.ref-note("fm")[Fernando Marson]\n';
      for (final (surface, id) in [('tylog', 't'), ('Fernando Marson', 'fm')]) {
        expect(
          linkMentionInline(
            source,
            EnrichMention(surface: surface, type: 'person', line: 3),
            entity(id, surface),
          ),
          source,
          reason: surface,
        );
      }
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
      final source = linkMentionInline(
        header,
        mention,
        silva,
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
