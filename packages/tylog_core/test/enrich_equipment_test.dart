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

NoteRef day(String date) => NoteRef(
  id: date,
  path: 'daily/$date.typ',
  title: date,
  kind: 'daily',
  outgoingLinks: const [],
);

VaultIndex indexOf(List<NoteRef> notes) => VaultIndex(
  notesByPath: {for (final note in notes) note.path: note},
  backlinksByTarget: const {},
);

EnrichMentions mentionsOf(List<EnrichMention> mentions) =>
    EnrichMentions(note: 'x', contentSha: 'x', mentions: mentions);

void main() {
  final units = [
    for (var i = 1; i <= 12; i++)
      entity(
        'TL-${i.toString().padLeft(4, '0')}',
        'Unit $i',
        kind: 'equipment',
        aliases: [
          'VR glasses $i',
          'VR glasses no. $i',
          'VR glasses nº $i',
          'TL-${i.toString().padLeft(4, '0')}',
          'TL${i.toString().padLeft(4, '0')}',
          'serial$i',
        ],
      ),
  ];
  EnrichMention mention(
    String surface, {
    String type = 'equipment',
    List<String> hints = const [],
  }) => EnrichMention(surface: surface, type: type, line: 1, hints: hints);
  List<EnrichDecision> resolve(
    String surface,
    EnrichMemory memory, {
    String type = 'equipment',
    List<String> hints = const [],
  }) => resolveMentions(
    mentionsOf([mention(surface, type: type, hints: hints)]),
    day('2026-10-01'),
    memory,
  );

  test('equipment key folds number markers without stripping words', () {
    for (final value in [
      'VR-glasses num3',
      'VR glasses no. 3',
      'VR glasses 3',
      'VR glasses nº 3',
      'vr glasses #3',
    ]) {
      expect(enrichEquipmentKey(value), 'vrglasses3');
    }
    expect(enrichEquipmentKey('VR-очки №3'), 'vrочки3');
    expect(enrichEquipmentKey('Anode number 3'), 'anode3');
    expect(
      enrichEquipmentKey('Equipment B'),
      isNot(enrichEquipmentKey('Equipment A')),
    );
    expect(enrichEquipmentKey('N°3 NR3 номер3'), '333');
  });

  test('numbered equipment resolves exactly without adjacent units', () {
    final memory = EnrichMemory.build(indexOf(units));
    final decision = resolve('VR-glasses num3', memory).single;
    expect(decision.status, EnrichStatus.linked);
    expect(decision.target?.id, 'TL-0003');
    expect(decision.candidates.map((c) => c.note.id), ['TL-0003']);
    expect(
      resolve(
        'VR glasses no. 1',
        memory,
      ).single.candidates.map((c) => c.note.id),
      ['TL-0001'],
    );
    expect(resolve('VR glasses', memory).single.status, EnrichStatus.review);
    expect(resolve('VR glasses', memory).single.candidates, hasLength(12));
  });

  test('Cyrillic aliases and board names resolve', () {
    final memory = EnrichMemory.build(
      indexOf([
        entity('ru', 'headset', kind: 'equipment', aliases: ['VR-очки 3']),
        entity('board', 'ESP32 board', kind: 'equipment'),
      ]),
    );
    expect(resolve('VR-очки №3', memory).single.target?.id, 'ru');
    expect(resolve('ESP32 board', memory).single.target?.id, 'board');
  });

  test('feedback is applied through the existing ledger', () {
    final memory = EnrichMemory.build(indexOf(units));
    memory.addFeedback(
      const EnrichFeedback(
        surface: 'VR-glasses num3',
        entity: 'TL-0003',
        accepted: true,
        note: 'd',
        at: 't',
      ),
    );
    expect(memory.acceptedCount('VR-glasses num3', 'TL-0003'), 1);
    memory.addFeedback(
      const EnrichFeedback(
        surface: 'VR glasses 3',
        entity: 'TL-0003',
        accepted: false,
        note: 'd',
        at: 't',
      ),
    );
    expect(memory.isRejected('VR glasses 3', 'TL-0003'), isTrue);
    expect(resolve('VR glasses 3', memory), isEmpty);
  });

  test('shared alias requires review and missing equipment is dropped', () {
    final memory = EnrichMemory.build(
      indexOf([
        entity('a', 'First', kind: 'equipment', aliases: ['Kit A']),
        entity('b', 'Second', kind: 'equipment', aliases: ['Kit A']),
      ]),
    );
    final decision = resolve('Kit A', memory).single;
    expect(decision.status, EnrichStatus.review);
    expect(
      decision.candidates.map((c) => c.note.id),
      unorderedEquals(['a', 'b']),
    );
    expect(resolve('unknown hardware', memory), isEmpty);
  });

  test(
    'equipment does not match person mentions and existing people still match',
    () {
      final memory = EnrichMemory.build(
        indexOf([
          entity('hardware', 'Ada board', kind: 'equipment'),
          entity('person', 'VR'),
        ]),
      );
      expect(
        resolve('Ada', memory, type: 'person').single.status,
        EnrichStatus.propose,
      );
      expect(resolve('VR', memory, type: 'person').single.target?.id, 'person');
    },
  );

  test('loans parse valid items and skip malformed items', () {
    final parsed = EnrichMentions.tryParse({
      'schema': 1,
      'note': 'd',
      'content_sha': 'x',
      'loans': [
        {'line': 3, 'borrower': 'Ada', 'purpose': 'demo', 'topic': 'VR'},
        {'line': 4},
        {'line': '5'},
        {'line': 6, 'borrower': 42},
        'bad',
      ],
    })!;
    expect(parsed.loans, hasLength(2));
    expect(
      (
        parsed.loans.first.line,
        parsed.loans.first.borrower,
        parsed.loans.first.purpose,
        parsed.loans.first.topic,
      ),
      (3, 'Ada', 'demo', 'VR'),
    );
    expect(parsed.loans.last.borrower, isNull);
    expect(const EnrichMentions(note: 'd', contentSha: 'x').loans, isEmpty);
  });
}
