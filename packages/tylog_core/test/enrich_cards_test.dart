import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:tylog_core/tylog_core.dart';

void main() {
  final dir = Directory('test/fixtures/lab_review');
  final files = {
    for (final f in dir.listSync().whereType<File>())
      if (f.path.endsWith('.typ') && !f.path.endsWith('day.typ'))
        'notes/${f.uri.pathSegments.last}': f.readAsStringSync(),
  };
  final daySource = File('${dir.path}/day.typ').readAsStringSync();
  const dayPath = 'daily/2026/11/2026-11-12.typ';
  final mentions = EnrichMentions.tryParse(
    jsonDecode(File('${dir.path}/mentions.json').readAsStringSync()),
  )!;

  EnrichDayResolution resolve(String source, EnrichMentions input) {
    final notes = {
      for (final e in files.entries) e.key: scanNote(e.key, e.value),
      dayPath: scanNote(dayPath, source),
    };
    final index = VaultIndex(notesByPath: notes, backlinksByTarget: const {});
    return resolveEnrichDay(
      input,
      notes[dayPath]!,
      EnrichMemory.build(index),
      index,
      source,
    );
  }

  List<EnrichLineCard> cards(
    String source,
    EnrichDayResolution r, {
    Map<String, List<TaskRef>> openLoans = const {},
  }) => enrichLineCards(
    decisions: r.decisions,
    loans: r.loans,
    lines: source.split('\n'),
    openLoans: openLoans,
  );

  String show(EnrichDayResolution r) => [
    for (final d in r.decisions)
      '${d.mention.line} ${d.mention.surface} ${d.status.name} ${d.target?.id}',
    for (final l in r.loans)
      'loan ${l.line} ${l.equipment.map((e) => e.id)} due ${l.due}',
  ].join('\n');

  List<String> rows(EnrichLineCard card) => [
    for (final row in card.rows)
      '${row.state.name}:${row.surface}:${row.target?.id}',
  ];

  test('lab day produces ordered cards and labels', () {
    final r = resolve(daySource, mentions);
    printOnFailure(show(r));
    final result = cards(daySource, r);
    expect(result.map((c) => c.line), [13, 14, 15]);
    expect(rows(result[0]), [
      'propose:Student 20231234:null',
      'willLink:lab:LAB',
      'willLink:ESP32 DevKit:TL-0102',
      'willLink:Soldering station A:TL-0103',
    ]);
    expect(rows(result[1]), [
      'willLink:José Graça:lab-person-7',
      'willLink:yellow Quest 3:TL-0201',
    ]);
    expect(rows(result[2]), [
      'propose:Студент 20239876:null',
      'willLink:QUEST 3 [2]:TL-0202',
    ]);
    expect(result[0].primaryLabel, 'Link 3 + track loan');
    expect(result[1].primaryLabel, 'Link 2 + track loan');
    final equipmentOnly = enrichLineCards(
      decisions: r.decisions
          .where((d) => d.mention.type == 'equipment')
          .toList(),
      loans: r.loans,
      lines: daySource.split('\n'),
    ).singleWhere((c) => c.line == 14);
    expect(equipmentOnly.primaryLabel, 'Link 1 + track loan');
    final due = r.loans.singleWhere((l) => l.line == 15).due;
    expect(due, isNotNull);
    expect(result[2].primaryLabel, 'Link 1 + track loan · due $due');
    for (final card in result) {
      for (final row in card.rows) {
        expect(
          card.text
              .substring(row.highlightStart, row.highlightEnd)
              .toLowerCase(),
          row.surface.toLowerCase(),
        );
      }
    }
  });

  test('inline equipment link becomes a linked row', () {
    final source = daySource.replaceFirst(
      'ESP32 DevKit',
      '#tylog.ref-note("TL-0102")[ESP32 DevKit]',
    );
    final r = resolve(source, mentions);
    printOnFailure(show(r));
    final card = cards(source, r).first;
    final row = card.rows.singleWhere((r) => r.target?.id == 'TL-0102');
    expect(row.state, EnrichRowState.linked);
    expect(row.decision, isNull);
    expect(
      card.text.substring(row.highlightStart, row.highlightEnd),
      'ESP32 DevKit',
    );
    expect(card.primaryLabel, 'Link ${card.willLinkCount} + track loan');
    expect(card.willLinkCount, 2);
  });

  test('ambiguous equipment and proposed student do not count as links', () {
    const source = '\n= Day\n- Student 5 asked for a Quest 3\n';
    final input = EnrichMentions.tryParse({
      'schema': 1,
      'note': dayPath,
      'content_sha': 'x',
      'mentions': [
        {'surface': 'Quest 3', 'type': 'equipment', 'line': 3},
      ],
    })!;
    final r = resolve(source, input);
    printOnFailure(show(r));
    final card = cards(source, r).single;
    expect(card.rows, hasLength(1));
    expect(card.rows.single.state, EnrichRowState.ambiguous);
    expect(card.rows.single.candidates.map((c) => c.note.id).toSet(), {
      'TL-0201',
      'TL-0202',
    });
    expect(card.primaryLabel, isNull);
    final proposed = cards(
      daySource,
      resolve(daySource, mentions),
    ).first.rows.first;
    expect(proposed.state, EnrichRowState.propose);
    expect(enrichPrimaryLabel(0, null), isNull);
  });

  test('open loan warning and stable key', () {
    const conflict = TaskRef(
      id: 'loan',
      notePath: 'a.typ',
      text: 'Loan',
      clocked: [ClockEntry(start: '2026-01-01T10:00:00Z')],
      properties: {'loan': true, 'borrower': 'Sam'},
    );
    final r = resolve(daySource, mentions);
    final first = cards(
      daySource,
      r,
      openLoans: {
        'TL-0102': [conflict],
      },
    ).first;
    expect(first.warning, loanOutSinceText(conflict));
    expect(first.key, cards(daySource, r).first.key);
    final changed = daySource.replaceFirst(
      'booked an appointment',
      'made an appointment',
    );
    expect(first.key, isNot(cards(changed, r).first.key));
  });
}
