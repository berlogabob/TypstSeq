import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:tylog_core/tylog_core.dart';

// Fixture from the P30 report of 2026-11-12: three lab lines, two loan hints.
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

  EnrichDayResolution resolve(
    String source, [
    List<EnrichFeedback> fb = const [],
  ]) {
    final notes = {
      for (final e in files.entries) e.key: scanNote(e.key, e.value),
      dayPath: scanNote(dayPath, source),
    };
    final index = VaultIndex(notesByPath: notes, backlinksByTarget: const {});
    final memory = EnrichMemory.build(index, fb);
    return resolveEnrichDay(mentions, notes[dayPath]!, memory, index, source);
  }

  // A day with the given lines and the LLM mentions in [extra].
  EnrichDayResolution resolveLines(
    List<String> body, {
    List<Map<String, Object?>> extra = const [],
    Map<String, String> more = const {},
    List<EnrichFeedback> fb = const [],
  }) {
    final source = '\n= Day\n${body.map((l) => '- $l').join('\n')}\n';
    final notes = {
      for (final e in {...files, ...more}.entries)
        e.key: scanNote(e.key, e.value),
      dayPath: scanNote(dayPath, source),
    };
    final index = VaultIndex(notesByPath: notes, backlinksByTarget: const {});
    final memory = EnrichMemory.build(index, fb);
    final m = EnrichMentions.tryParse({
      'schema': 1,
      'note': dayPath,
      'content_sha': 'x',
      'mentions': extra,
    })!;
    return resolveEnrichDay(m, notes[dayPath]!, memory, index, source);
  }

  Map<String, Object?> mention(String surface, int line, String type) => {
    'surface': surface,
    'type': type,
    'line': line,
  };

  List<EnrichDecision> equipmentOf(EnrichDayResolution r) => [
    for (final d in r.decisions)
      if (d.mention.type == 'equipment') d,
  ];

  String show(EnrichDayResolution r) => [
    for (final d in r.decisions)
      '${d.mention.line} ${d.mention.surface} ${d.status.name} ${d.target?.id}',
    for (final l in r.loans) 'loan ${l.line} ${l.equipment.map((e) => e.id)}',
  ].join('\n');

  test('every line of the day yields chips and loans', () {
    final r = resolve(daySource);
    printOnError(r);
    final lines = r.decisions.map((d) => d.mention.line).toSet();
    expect(lines, containsAll([13, 14, 15]), reason: show(r));
    expect(r.loans.map((l) => l.line), containsAll([13, 15]), reason: show(r));
  });

  test('the yellow Quest 3 resolves to TL-0201 and offers a loan', () {
    final r = resolve(daySource);
    final d = r.decisions.firstWhere(
      (d) => d.mention.line == 14 && d.mention.type == 'equipment',
    );
    expect(d.mention.surface, 'yellow Quest 3');
    expect(d.target?.id, 'TL-0201');
    expect(d.candidates, hasLength(1));
    expect(d.choose, isFalse);
    expect(
      r.loans.where((l) => l.line == 14).single.equipment.single.id,
      'TL-0201',
    );
  });

  test('colour words resolve without the note listing them', () {
    final r = resolveLines(['Student 1 took the blue headset']);
    expect(equipmentOf(r).single.target?.id, 'TL-0202');
    expect(equipmentOf(r).single.mention.surface, 'blue headset');
    expect(r.loans.single.equipment.single.id, 'TL-0202');
  });

  test('Russian colours with case endings resolve', () {
    var r = resolveLines(['Студент взял жёлтый Quest 3']);
    expect(equipmentOf(r).single.target?.id, 'TL-0201');
    r = resolveLines(['Студент взял синюю гарнитуру']);
    expect(equipmentOf(r).single.target?.id, 'TL-0202');
    expect(equipmentOf(r).single.mention.surface, 'синюю гарнитуру');
  });

  test('a bare Quest 3 is one chooser with two candidates, no loan yet', () {
    final r = resolveLines(
      ['Student 5 asked for a Quest 3'],
      extra: [mention('Quest 3', 1, 'equipment')],
    );
    final eq = equipmentOf(r);
    expect(eq, hasLength(1), reason: show(r));
    expect(eq.single.choose, isTrue);
    expect(eq.single.candidates.map((c) => c.note.id).toSet(), {
      'TL-0201',
      'TL-0202',
    });
    expect(r.loans, isEmpty);
  });

  test('choosing records an accept and the loan offer appears', () {
    final chosen = EnrichFeedback(
      surface: 'Quest 3',
      entity: 'TL-0202',
      accepted: true,
      note: dayPath,
      at: '2026-11-12T10:00:00Z',
    );
    // The accept flow writes the link inline; the line then offers a loan.
    final r = resolveLines(
      ['Student 5 asked for a #tylog.ref-note("TL-0202")[Quest 3]'],
      extra: [mention('Quest 3', 1, 'equipment')],
      fb: [chosen],
    );
    expect(equipmentOf(r), isEmpty);
    expect(r.loans.single.equipment.single.id, 'TL-0202');
  });

  test('a user-added alias resolves', () {
    final edited = files['notes/TL-0201.typ']!.replaceFirst(
      '"гарнитура",)',
      '"гарнитура", "жёлтый шлем",)',
    );
    final r = resolveLines(
      ['Студент 7 взял жёлтый шлем'],
      more: {'notes/TL-0201.typ': edited},
    );
    expect(equipmentOf(r).single.target?.id, 'TL-0201');
  });

  test('an alias inside a longer word does not match', () {
    final r = resolveLines([
      'Student 7 read about the Quest 3D engine and TL-02011',
    ]);
    expect(equipmentOf(r), isEmpty, reason: show(r));
  });

  test('accepting the ESP32 link keeps lines 14 and 15 visible', () {
    final esp = scanNote('notes/TL-0102.typ', files['notes/TL-0102.typ']!);
    final linked = linkMentionInline(daySource, mentions.mentions[2], esp);
    expect(linked, isNot(daySource));
    final r = resolve(linked);
    final lines = r.decisions.map((d) => d.mention.line).toSet();
    expect(lines, containsAll([14, 15]), reason: show(r));
    expect(r.loans.map((l) => l.line), containsAll([13, 15]), reason: show(r));
  });
}

void printOnError(EnrichDayResolution r) {}
