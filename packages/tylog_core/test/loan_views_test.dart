import 'package:test/test.dart';
import 'package:tylog_core/tylog_core.dart';

void main() {
  const old = ClockEntry(
    start: '2026-01-01T10:00:00Z',
    end: '2026-01-01T11:00:00Z',
  );
  const running = ClockEntry(start: '2026-01-02T10:00:00Z');
  const tasks = [
    TaskRef(
      id: 'old',
      notePath: 'a',
      text: 'Old',
      status: 'done',
      clocked: [old],
      properties: {
        'loan': true,
        'equipment': ['a'],
      },
    ),
    TaskRef(
      id: 'new',
      notePath: 'a',
      text: 'New',
      clocked: [running],
      properties: {
        'loan': true,
        'equipment': ['a', 'b'],
      },
    ),
    TaskRef(
      id: 'tie',
      notePath: 'z',
      text: 'Tie',
      clocked: [running],
      properties: {'loan': true, 'equipment': '("a",)'},
    ),
    TaskRef(
      id: 'none',
      notePath: 'a',
      text: 'No clock',
      status: 'cancelled',
      properties: {
        'loan': true,
        'equipment': ['a'],
      },
    ),
    TaskRef(
      id: 'other',
      notePath: 'a',
      text: 'Other',
      clocked: [running],
      properties: {
        'equipment': ['a'],
      },
    ),
  ];
  const index = VaultIndex(
    notesByPath: {},
    backlinksByTarget: {},
    tasks: tasks,
  );

  test('open loans and equipment history are newest first', () {
    expect(openLoanTasks(index).map((t) => t.id), ['tie', 'new']);
    expect(loanHistoryFor(index, 'a').map((t) => t.id), [
      'tie',
      'new',
      'old',
      'none',
    ]);
    expect(loanHistoryFor(index, 'b').map((t) => t.id), ['new']);
    expect(loanHistoryFor(index, 'missing'), isEmpty);
  });

  test('groups open loans and finds the oldest matching equipment loan', () {
    const older = TaskRef(
      id: 'older', notePath: 'a', text: 'Older',
      clocked: [old],
      properties: {'loan': true, 'equipment': ['b']},
    );
    const groupedIndex = VaultIndex(
      notesByPath: {}, backlinksByTarget: {}, tasks: [...tasks, older],
    );
    final grouped = openLoansByEquipment(groupedIndex);
    expect(grouped['a']!.map((task) => task.id), ['tie', 'new']);
    expect(grouped['b']!.map((task) => task.id), ['new', 'older']);
    const offer = EnrichLoanOffer(
      line: 1, text: '', ledgerSurface: '',
      equipment: [
        NoteRef(id: 'a', path: 'a', title: 'A', kind: 'equipment', outgoingLinks: []),
        NoteRef(id: 'b', path: 'b', title: 'B', kind: 'equipment', outgoingLinks: []),
      ],
    );
    expect(openLoanFor(offer, grouped), same(older));
    expect(openLoanFor(offer, {}), isNull);
    expect(openLoanFor(offer, {'a': [tasks[2], tasks[1]]}), same(tasks[2]));
  });

  test('out since text uses borrower, assignee, or neither', () {
    const borrower = TaskRef(
      id: 'a', notePath: 'a', text: '', clocked: [old],
      assignees: ['Alex'], properties: {'borrower': 'Sam'},
    );
    const assignee = TaskRef(
      id: 'b', notePath: 'a', text: '', clocked: [old],
      assignees: ['Alex'], properties: {'borrower': ''},
    );
    expect(loanOutSinceText(borrower), 'Already out since 2026-01-01 (Sam)');
    expect(loanOutSinceText(assignee), 'Already out since 2026-01-01 (Alex)');
    expect(loanOutSinceText(tasks[1]), 'Already out since 2026-01-02');
  });

  test('duration spans first start to last end or now', () {
    final now = DateTime.utc(2026, 1, 2, 12, 10);
    expect(loanOutFor(tasks[1], now), const Duration(hours: 2, minutes: 10));
    expect(loanOutFor(tasks[0], now), const Duration(hours: 1));
    expect(loanOutFor(tasks[3], now), isNull);
    const multiple = TaskRef(
      id: 'm',
      notePath: 'a',
      text: '',
      clocked: [
        old,
        ClockEntry(start: '2026-01-01T12:00:00Z', end: '2026-01-01T13:00:00Z'),
      ],
    );
    expect(loanOutFor(multiple, now), const Duration(hours: 3));
  });
}
