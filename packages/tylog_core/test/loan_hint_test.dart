import 'dart:io';

import 'package:test/test.dart';
import 'package:tylog_core/tylog_core.dart';
import 'package:tylog_core/src/enrich_alias.dart';

void main() {
  EnrichMentions apply(String line, {String? person, EnrichLoanHint? hint}) =>
      applyAliasHits(
        EnrichMentions(
          note: 'day',
          contentSha: '',
          mentions: [
            if (person != null)
              EnrichMention(surface: person, type: 'person', line: 1),
          ],
          loans: [?hint],
        ),
        [
          const EnrichAliasHit(1, 'Quest 3', ['TL-0201']),
        ],
        [line],
      );

  test('synthesizes borrowers and purposes from lab lines', () {
    final cases = <(String, String?, String?, String)>[
      (
        'Student 20231234 booked an appointment and used Quest 3',
        null,
        'Student 20231234',
        'consultation',
      ),
      (
        'for José Graça class student asked to use the yellow Quest 3',
        'José Graça',
        'student',
        'class',
      ),
      (
        'Студент 20239876 взял QUEST 3 домой',
        null,
        'Студент 20239876',
        'take-home',
      ),
      (
        'para a aula de José Graça o aluno 123 levou a Quest 3 para casa',
        'José Graça',
        'aluno 123',
        'class',
      ),
      (
        'для занятия José Graça студент 20239876 взял QUEST 3 домой',
        'José Graça',
        'студент 20239876',
        'class',
      ),
      ('Андрей взял QUEST 3', 'Андрей', 'Андрей', 'lab'),
      ('for José Graça class Quest 3', 'José Graça', 'José Graça', 'class'),
      ('на пару José Graça Quest 3', 'José Graça', 'José Graça', 'class'),
      (
        'para a turma de José Graça aluno 2 Quest 3',
        'José Graça',
        'aluno 2',
        'class',
      ),
      (
        'José Graça took Quest 3 for the weekend',
        'José Graça',
        'José Graça',
        'take-home',
      ),
      (
        'José Graça uses Quest 3 for research in the lab',
        'José Graça',
        'José Graça',
        'research',
      ),
      ('Жозе взял Quest 3 на выходные', 'Жозе', 'Жозе', 'take-home'),
      ('José levou o Quest 3 para casa', 'José', 'José', 'take-home'),
      ('José usa Quest 3 para investigação', 'José', 'José', 'research'),
      ('José usa Quest 3 para pesquisa', 'José', 'José', 'research'),
      ('Жозе использует Quest 3 для исследования', 'Жозе', 'Жозе', 'research'),
    ];
    for (final (line, person, borrower, purpose) in cases) {
      final hint = apply(line, person: person).loans.single;
      expect((hint.borrower, hint.purpose), (borrower, purpose), reason: line);
    }
  });

  test('corrects only a teacher borrower in a sidecar hint on plain text', () {
    const line =
        'for #tylog.ref-note("teacher")[José Graça] class student 123 took Quest 3';
    final corrected = apply(
      line,
      person: 'José Graça',
      hint: const EnrichLoanHint(line: 1, borrower: 'José Graça', topic: 'VR'),
    ).loans.single;
    expect(
      (corrected.borrower, corrected.purpose, corrected.topic),
      ('student 123', 'class', 'VR'),
    );
    final kept = apply(
      line,
      person: 'José Graça',
      hint: const EnrichLoanHint(line: 1, borrower: 'student', purpose: 'lab'),
    ).loans.single;
    expect((kept.borrower, kept.purpose), ('student 123', 'class'));
    final alone = apply(
      'for José Graça class Quest 3',
      person: 'José Graça',
      hint: const EnrichLoanHint(
        line: 1,
        borrower: 'José Graça',
        purpose: 'lab',
      ),
    ).loans.single;
    expect((alone.borrower, alone.purpose), ('José Graça', 'class'));
    final subject = apply(
      'José Graça uses Quest 3 for research',
      person: 'José Graça',
      hint: const EnrichLoanHint(line: 1, purpose: 'research'),
    ).loans.single;
    expect((subject.borrower, subject.purpose), ('José Graça', 'research'));
  });

  test('writes and compiles a synthesized teacher-class loan', () {
    const line =
        '- for #tylog.ref-note("lab-person-7")[José Graça] class student asked to use the yellow Quest 3';
    const source =
        '#show: tylog.note.with(id: "day", title: "Day", kind: "daily")\n\n$line\n';
    const teacher = NoteRef(
      id: 'lab-person-7',
      path: 'teacher.typ',
      title: 'José Graça',
      kind: 'person',
      outgoingLinks: [],
    );
    const equipment = NoteRef(
      id: 'TL-0201',
      path: 'quest.typ',
      title: 'yellow Quest 3',
      kind: 'equipment',
      outgoingLinks: [],
    );
    const day = NoteRef(
      id: 'day',
      path: 'day.typ',
      title: 'Day',
      kind: 'daily',
      outgoingLinks: [],
    );
    final memory = EnrichMemory.build(
      VaultIndex(
        notesByPath: {teacher.path: teacher, equipment.path: equipment},
        backlinksByTarget: const {},
      ),
    );
    final hints = applyAliasHits(
      const EnrichMentions(
        note: 'day',
        contentSha: '',
        mentions: [
          EnrichMention(surface: 'José Graça', type: 'person', line: 3),
        ],
      ),
      const [
        EnrichAliasHit(3, 'yellow Quest 3', ['TL-0201']),
      ],
      source.split('\n'),
    );
    final offer = enrichLoanOffers(
      hints,
      source,
      memory,
      resolveMentions(hints, day, memory),
    ).single;
    final result = trackAsLoan(
      source,
      offer,
      'loan-class',
      DateTime.utc(2026, 11, 12, 10),
    );
    expect(
      result,
      '#show: tylog.note.with(id: "day", title: "Day", kind: "daily")\n\n'
      '#tylog.task(\n  id: "loan-class",\n  text: "for José Graça class student asked to use the yellow Quest 3",\n'
      '  assignees: ("lab-person-7",),\n'
      '  properties: ("loan": true, "purpose": "class", "equipment": ("TL-0201",), "borrower": "student", "clocked": (("2026-11-12T10:00:00.000Z", none),),),\n'
      '  status: "doing",\n)\n',
    );
    if (Process.runSync('which', ['typst']).exitCode != 0) return;
    final repo = Directory.current.parent.parent;
    final dir = Directory('${repo.path}/.dart_tool/loan_hint_test')
      ..createSync(recursive: true);
    try {
      final file = File('${dir.path}/loan.typ')
        ..writeAsStringSync('#import "/typst/tylog/lib.typ" as tylog\n$result');
      final compiled = Process.runSync('typst', [
        'compile',
        '--root',
        repo.path,
        file.path,
        '${file.path}.pdf',
      ]);
      expect(compiled.exitCode, 0, reason: '${compiled.stderr}');
    } finally {
      dir.deleteSync(recursive: true);
    }
  });
}
