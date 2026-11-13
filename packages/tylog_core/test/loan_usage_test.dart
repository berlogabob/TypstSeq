import 'package:test/test.dart';
import 'package:tylog_core/tylog_core.dart';

void main() {
  final index = VaultIndex(
    notesByPath: {},
    backlinksByTarget: {},
    tasks: const [
      TaskRef(
        id: 'one',
        notePath: 'day',
        text: 'First',
        status: 'done',
        clocked: [
          ClockEntry(
            start: '2026-11-10T09:00:00Z',
            end: '2026-11-10T12:00:00Z',
          ),
        ],
        assignees: ['Ada'],
        properties: {
          'loan': true,
          'equipment': ['camera'],
          'purpose': 'field',
          'borrower': 'Sam',
        },
      ),
      TaskRef(
        id: 'two',
        notePath: 'day',
        text: 'Overlap',
        clocked: [ClockEntry(start: '2026-11-10T11:00:00Z')],
        properties: {
          'loan': true,
          'equipment': ['camera'],
          'purpose': 'lab',
        },
      ),
    ],
  );

  test(
    'merges overlapping and open intervals, splits purpose and borrowers',
    () {
      final usage = equipmentUsage(
        index,
        to: DateTime.utc(2026, 11, 10, 13),
      )['camera']!;
      expect(usage.loans, 2);
      expect(usage.hoursOut, 4);
      expect(usage.hoursByPurpose, {'field': 3, 'lab': 2});
      expect(usage.borrowers, {'Sam', 'Ada'});
      expect(usage.lastReturned, DateTime.utc(2026, 11, 10, 12));
    },
  );

  test('clips clock intervals to the requested window', () {
    final usage = equipmentUsage(
      index,
      from: DateTime.utc(2026, 11, 10, 10),
      to: DateTime.utc(2026, 11, 10, 11, 30),
    )['camera']!;
    expect(usage.hoursOut, 1.5);
    expect(usage.hoursByPurpose, {'field': 1.5, 'lab': 0.5});
  });

  test('a naive start (older loans) reads as device-local, Z end as UTC', () {
    final startLocal = DateTime(2026, 11, 10, 9);
    final naive = startLocal.toIso8601String();
    expect(naive.endsWith('Z'), isFalse);
    final end = startLocal.toUtc().add(const Duration(hours: 3));
    final mixed = VaultIndex(
      notesByPath: {},
      backlinksByTarget: {},
      tasks: [
        TaskRef(
          id: 'old',
          notePath: 'day',
          text: 'Old loan',
          status: 'done',
          clocked: [ClockEntry(start: naive, end: end.toIso8601String())],
          properties: const {
            'loan': true,
            'equipment': ['cam'],
          },
        ),
      ],
    );
    final usage = equipmentUsage(
      mixed,
      to: end.add(const Duration(hours: 1)),
    )['cam']!;
    expect(usage.hoursOut, 3);
    final task = mixed.tasks.single;
    expect(loanOutFor(task, end), const Duration(hours: 3));
  });
}
