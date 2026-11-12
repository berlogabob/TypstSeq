import 'dart:io';

import 'package:test/test.dart';
import 'package:tylog_core/tylog_core.dart';

NoteRef entity(
  String id,
  String title,
  String kind, {
  List<String> aliases = const [],
}) => NoteRef(
  id: id,
  path: 'notes/$id.typ',
  title: title,
  kind: kind,
  aliases: aliases,
  outgoingLinks: const [],
);

void main() {
  const header =
      '#show: tylog.note.with(id: "day", title: "Day", kind: "daily")\n\n';
  const ru =
      '- 11:20 Для занятия у #tylog.ref-note("lab-person-4")[Жозе Граса] студент взял #tylog.ref-note("TL-0003")[VR-очки №3]';
  const en =
      '- 14:05 Student 2031 booked an appointment in the lab, asked for #tylog.ref-note("TL-0007")[Equipment A] and #tylog.ref-note("TL-0008")[B], has problems with the ESP32 library';
  final notes = [
    entity('lab-person-4', 'Жозе Граса', 'person'),
    entity('TL-0003', 'VR-очки №3', 'equipment'),
    entity('TL-0007', 'Equipment A', 'equipment'),
    entity('TL-0008', 'B', 'equipment'),
  ];
  final day = entity('day', 'Day', 'daily');
  EnrichMemory memory() => EnrichMemory.build(
    VaultIndex(
      notesByPath: {for (final n in notes) n.path: n},
      backlinksByTarget: const {},
    ),
  );
  List<EnrichLoanOffer> offers(
    String source,
    EnrichMentions mentions,
    EnrichMemory mem,
  ) => enrichLoanOffers(
    mentions,
    source,
    mem,
    resolveMentions(mentions, day, mem),
  );
  final now = DateTime.utc(2026, 11, 12, 10);
  final repo = Directory.current.path.endsWith('packages/tylog_core')
      ? Directory.current.parent.parent.path
      : Directory.current.path;
  final tmp = Directory('$repo/.dart_tool/loan_test');
  setUpAll(() => tmp.createSync(recursive: true));
  tearDownAll(() => tmp.deleteSync(recursive: true));

  test('Russian loan preserves the note and scans as a running task', () async {
    const source = '$header$ru\n\nAfter.\n';
    const mentions = EnrichMentions(
      note: 'day',
      contentSha: '',
      loans: [EnrichLoanHint(line: 3, borrower: 'студент', purpose: 'class')],
    );
    final offer = offers(source, mentions, memory()).single;
    expect(offer.person?.id, 'lab-person-4');
    final result = trackAsLoan(source, offer, 'loan-ru', now);
    expect(
      result,
      '$header#tylog.task(\n'
      '  id: "loan-ru",\n'
      '  text: "11:20 Для занятия у Жозе Граса студент взял VR-очки №3",\n'
      '  assignees: ("lab-person-4",),\n'
      '  properties: ("loan": true, "purpose": "class", "equipment": ("TL-0003",), "borrower": "студент", "clocked": (("2026-11-12T10:00:00.000Z", none),),),\n'
      '  status: "doing",\n'
      ')\n\nAfter.\n',
    );
    expect(trackAsLoan(result, offer, 'loan-ru', now), result);
    final vault = Directory('${tmp.path}/vault')..createSync(recursive: true);
    final daily = Directory('${vault.path}/daily')..createSync(recursive: true);
    File('${daily.path}/day.typ').writeAsStringSync(result);
    final task = (await scanVaultStorage(
      LocalVaultStorage(vault),
    )).tasks.single;
    expect(task.status, 'doing');
    expect(task.runningClock, isNotNull);
    expect(task.assignees, ['lab-person-4']);
    expect(task.properties['loan'], true);
    expect(loanEquipmentIds(task), ['TL-0003']);
    expect(isOpenLoan(task), isTrue);
    expect(task.properties['purpose'], 'class');
    if (Process.runSync('which', ['typst']).exitCode != 0) {
      markTestSkipped('typst not on PATH');
      return;
    }
    final file = File('${tmp.path}/loan.typ')
      ..writeAsStringSync('#import "/typst/tylog/lib.typ" as tylog\n$result');
    final compiled = Process.runSync('typst', [
      'compile',
      '--root',
      repo,
      file.path,
      '${file.path}.pdf',
    ]);
    expect(compiled.exitCode, 0, reason: '${compiled.stderr}');
  });

  test('day resolution includes loans until the line is converted', () {
    const source = '$header$ru\n';
    const mentions = EnrichMentions(
      note: 'day',
      contentSha: '',
      loans: [EnrichLoanHint(line: 3, borrower: 'студент', purpose: 'class')],
    );
    final index = VaultIndex(
      notesByPath: {for (final n in notes) n.path: n},
      backlinksByTarget: const {},
    );
    final mem = memory();
    final offer = resolveEnrichDay(
      mentions,
      day,
      mem,
      index,
      source,
    ).loans.single;
    expect(offer.equipment.single.id, 'TL-0003');
    expect(offer.ledgerSurface, enrichPlainLine(ru));
    final tracked = trackAsLoan(source, offer, 'loan-ru', now);
    expect(resolveEnrichDay(mentions, day, mem, index, tracked).loans, isEmpty);
  });

  test('second loan in a note survives the first one growing the file', () {
    const source = '$header$ru\n$en\n';
    final mentionsJson = {
      'loans': [
        {'line': 3, 'purpose': 'class'},
        {'line': 4, 'purpose': 'consultation'},
      ],
      'mentions': <Object?>[],
    };
    EnrichMentions parse(Map<String, Object?> json) => EnrichMentions.tryParse({
      'note': 'day',
      'schema': 1,
      'content_sha': '',
      'mentions': <Object?>[],
      ...json,
    })!;
    final index = VaultIndex(
      notesByPath: {for (final n in notes) n.path: n},
      backlinksByTarget: const {},
    );
    final mem = memory();
    final first = resolveEnrichDay(
      parse(mentionsJson),
      day,
      mem,
      index,
      source,
    ).loans.first;
    final tracked = trackAsLoan(source, first, 'loan-ru', now);
    final shifted = shiftEnrichLines(
      mentionsJson,
      first.line,
      tracked.split('\n').length - source.split('\n').length,
    );
    final rest = resolveEnrichDay(
      parse(shifted),
      day,
      mem,
      index,
      tracked,
    ).loans;
    expect(rest.single.equipment.map((e) => e.id), ['TL-0007', 'TL-0008']);
    expect(trackAsLoan(tracked, rest.single, 'loan-en', now), isNot(tracked));
    // Without the shift the second hint points into the task block.
    expect(
      resolveEnrichDay(parse(mentionsJson), day, mem, index, tracked).loans,
      isEmpty,
    );
  });

  test('English loan resolves both equipment links', () {
    const source = '$header$en\n';
    const hints = EnrichMentions(
      note: 'day',
      contentSha: '',
      loans: [
        EnrichLoanHint(
          line: 3,
          borrower: 'Student 2031',
          purpose: 'consultation',
          topic: 'ESP32 library',
        ),
      ],
    );
    final offer = offers(source, hints, memory()).single;
    expect(offer.equipment.map((e) => e.id), ['TL-0007', 'TL-0008']);
    expect(offer.text, startsWith('14:05 Student 2031'));
    expect(
      (offer.borrower, offer.purpose, offer.topic),
      ('Student 2031', 'consultation', 'ESP32 library'),
    );
    expect(loanTaskId('day', offer), matches(RegExp(r'^loan-[0-9a-f]{8}$')));
  });

  test(
    'linked decisions work without links, but review and rejection do not',
    () {
      const source = '$header- 12:00 Equipment A\n';
      const hints = EnrichMentions(
        note: 'day',
        contentSha: '',
        mentions: [
          EnrichMention(surface: 'Equipment A', type: 'equipment', line: 3),
        ],
        loans: [EnrichLoanHint(line: 3)],
      );
      final mem = memory();
      expect(offers(source, hints, mem).single.equipment.single.id, 'TL-0007');
      final review = EnrichDecision(
        hints.mentions.single,
        EnrichStatus.review,
        [EnrichCandidate(notes[2], 0, strong: false)],
      );
      expect(enrichLoanOffers(hints, source, mem, [review]), isEmpty);
      mem.addFeedback(
        EnrichFeedback(
          surface: enrichPlainLine(source.split('\n')[2]),
          entity: enrichLoanEntity,
          accepted: false,
          note: 'day',
          at: 'now',
        ),
      );
      expect(offers(source, hints, mem), isEmpty);
    },
  );

  test('call lines and stale or duplicate edits are safe', () {
    const source = '$header#tylog.task(\n  text: "Equipment A",\n)\n';
    const hints = EnrichMentions(
      note: 'day',
      contentSha: '',
      loans: [EnrichLoanHint(line: 4)],
    );
    expect(offers(source, hints, memory()), isEmpty);
    final offer = EnrichLoanOffer(
      line: 4,
      text: '  text: "Equipment A",',
      ledgerSurface: 'text: "Equipment A",',
      equipment: [notes[2]],
    );
    expect(trackAsLoan(source, offer, 'new', now), source);
    const plain = '$header$en\n';
    final valid = offers(
      plain,
      const EnrichMentions(
        note: 'day',
        contentSha: '',
        loans: [EnrichLoanHint(line: 3)],
      ),
      memory(),
    ).single;
    expect(
      trackAsLoan(plain.replaceFirst('Student', 'Pupil'), valid, 'x', now),
      plain.replaceFirst('Student', 'Pupil'),
    );
    expect(trackAsLoan(plain, valid, 'day', now), plain);
  });

  test('two loans stay doing with running clocks', () {
    const source = '$header$ru\n$en\n';
    const hints = EnrichMentions(
      note: 'day',
      contentSha: '',
      loans: [EnrichLoanHint(line: 3), EnrichLoanHint(line: 4)],
    );
    final first = offers(source, hints, memory()).first;
    final one = trackAsLoan(source, first, 'one', now);
    final second = offers(
      one,
      const EnrichMentions(
        note: 'day',
        contentSha: '',
        loans: [EnrichLoanHint(line: 10)],
      ),
      memory(),
    ).single;
    final two = trackAsLoan(one, second, 'two', now);
    final calls = locateTypstCalls(two, names: {'tylog.task'});
    expect(calls, hasLength(2));
    for (final call in calls) {
      expect(taskField(call.source, 'status'), 'doing');
      expect(parseClockedField(call.source).single.isRunning, isTrue);
    }
  });
}
