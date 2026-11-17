import 'dart:io';
import 'package:test/test.dart';
import 'package:tylog_core/tylog_core.dart';

void main() {
  const one = NoteRef(
    id: 'TL-0007',
    path: 'one.typ',
    title: 'Quest 3 unit 1 TL-0007',
    kind: 'equipment',
    aliases: ['Quest 3 unit 1'],
    properties: {'item': 'Quest 3', 'unit': 1},
    outgoingLinks: [],
  );
  const two = NoteRef(
    id: 'TL-0008',
    path: 'two.typ',
    title: 'Quest 3 unit 2 TL-0008',
    kind: 'equipment',
    aliases: ['Quest 3 unit 2'],
    properties: {'item': 'Quest 3', 'unit': 2},
    outgoingLinks: [],
  );
  const ana = NoteRef(
    id: 'ana',
    path: 'ana.typ',
    title: 'Ana Silva',
    kind: 'person',
    outgoingLinks: [],
  );
  const task = TaskRef(
    id: 'existing',
    notePath: 'old.typ',
    text: 'old',
    status: 'doing',
    properties: {
      'loan': true,
      'equipment': ['TL-0007'],
    },
  );
  const index = VaultIndex(
    notesByPath: {'one.typ': one, 'two.typ': two, 'ana.typ': ana},
    backlinksByTarget: {},
    tasks: [task],
  );
  final date = DateTime.utc(2026, 11, 16);
  test('parses commands, dates and ambiguity without a sidecar', () {
    final offers = typedLoanOffers(
      '/loan out Quest 3 unit 1 to Ana Silva due friday\n/LOAN sai Quest 3 #1 to Unknown\n/loan выдать Quest 3 №1 to Ana Silva\n/loan return Quest 3 [1]\n/loan devolve Quest 3 unit 1\n/loan вернуть Quest 3 unit 1\n/loan out Quest 3 to Ana Silva\n```\n/loan out Quest 3 unit 1 to Ana Silva\n```',
      'day',
      index,
      noteDate: date,
    );
    expect(offers.length, 7);
    expect(offers.first.person?.id, 'ana');
    expect(offers.first.due, '2026-11-20');
    expect(offers[1].borrower, 'Unknown');
    expect(
      offers.take(6).every((o) => o.equipment.single.id == one.id),
      isTrue,
    );
    expect(
      offers
          .skip(3)
          .take(3)
          .every((o) => o.isReturn && o.openLoan?.id == 'existing'),
      isTrue,
    );
    expect(offers.last.equipment, isEmpty);
    expect(offers.last.equipmentCandidates.length, 2);
    expect(
      typedLoanCommand(offers.first),
      '/loan out Quest 3 unit 1 TL-0007 to Ana Silva due 2026-11-20',
    );
  });
  test('return marks the matching loan and removes only the command', () {
    const source =
        '#tylog.task(id: "existing", text: "old", status: "doing", properties: ("loan": true, "equipment": ("TL-0007",),))\n/loan return Quest 3 unit 1\nAfter';
    final offer = typedLoanOffers(source, 'day', index).single;
    final result = returnTypedLoan(
      source,
      offer,
      task,
      DateTime.utc(2026, 11, 17),
    );
    expect(result, contains('status: "done"'));
    expect(result, isNot(contains('/loan return')));
    expect(result, endsWith('\nAfter'));
  });
  test('typed out writes a compilable task', () {
    const source = '/loan out Quest 3 unit 1 to Ana Silva due friday';
    final offer = typedLoanOffers(source, 'day', index, noteDate: date).single;
    final result = trackAsLoan(
      source,
      offer,
      'loan-typed',
      DateTime.utc(2026, 11, 16),
    );
    expect(
      result,
      '#tylog.task(\n  id: "loan-typed",\n  text: "/loan out Quest 3 unit 1 to Ana Silva due friday",\n  assignees: ("ana",),\n  due: "2026-11-20",\n  properties: ("loan": true, "channel": "typed", "equipment": ("TL-0007",), "borrower": "Ana Silva", "clocked": (("2026-11-16T00:00:00.000Z", none),),),\n  status: "doing",\n)',
    );
    if (Process.runSync('which', ['typst']).exitCode != 0) {
      markTestSkipped('typst not on PATH');
      return;
    }
    final repo = Directory.current.parent.parent.path;
    final dir = Directory('$repo/.dart_tool/typed_loan_test')
      ..createSync(recursive: true);
    try {
      final file = File('${dir.path}/loan.typ')
        ..writeAsStringSync('#import "/typst/tylog/lib.typ" as tylog\n$result');
      final compiled = Process.runSync('typst', [
        'compile',
        '--root',
        repo,
        file.path,
        '${file.path}.pdf',
      ]);
      expect(compiled.exitCode, 0, reason: '${compiled.stderr}');
    } finally {
      dir.deleteSync(recursive: true);
    }
  });
}
