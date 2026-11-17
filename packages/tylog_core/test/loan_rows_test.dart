import 'package:test/test.dart';
import 'package:tylog_core/tylog_core.dart';

void main() {
  test('loanRows exports open and returned loans in path and id order', () {
    final localStart = DateTime(2026, 11, 10, 9).toIso8601String();
    final localEnd = DateTime(2026, 11, 10, 11).toIso8601String();
    final index = VaultIndex(
      notesByPath: {},
      backlinksByTarget: {},
      tasks: [
        TaskRef(
          id: 'b',
          notePath: 'notes/z.typ',
          text: 'Returned',
          status: 'done',
          due: '2026-11-11',
          assignees: const ['Ada'],
          clocked: [ClockEntry(start: localStart, end: localEnd)],
          properties: const {
            'loan': true,
            'equipment': '("TAG-2",)',
            'borrower': 'Sam',
            'purpose': 'lab',
            'channel': 'manual',
          },
        ),
        TaskRef(
          id: 'a',
          notePath: 'notes/a.typ',
          text: 'Open',
          status: 'doing',
          clocked: [ClockEntry(start: localStart)],
          properties: const {
            'loan': true,
            'equipment': ['TAG-1'],
          },
        ),
        TaskRef(id: 'not-loan', notePath: 'notes/ignored.typ', text: 'Ignored'),
      ],
    );

    expect(loanRows(index), [
      {
        'id': 'a',
        'path': 'notes/a.typ',
        'status': 'doing',
        'equipment': ['TAG-1'],
        'borrower': null,
        'assignees': <String>[],
        'purpose': null,
        'due': null,
        'start': DateTime.parse(localStart).toUtc().toIso8601String(),
        'end': null,
        'open': true,
        'channel': 'llm',
      },
      {
        'id': 'b',
        'path': 'notes/z.typ',
        'status': 'done',
        'equipment': ['TAG-2'],
        'borrower': 'Sam',
        'assignees': ['Ada'],
        'purpose': 'lab',
        'due': '2026-11-11',
        'start': DateTime.parse(localStart).toUtc().toIso8601String(),
        'end': DateTime.parse(localEnd).toUtc().toIso8601String(),
        'open': false,
        'channel': 'manual',
      },
    ]);
  });
}
