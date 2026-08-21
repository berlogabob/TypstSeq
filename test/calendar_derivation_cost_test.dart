import 'package:flutter_test/flutter_test.dart';
import 'package:tylog_core/models.dart';

/// `VaultIndex.calendar` is a computed getter: it walks every note **twice**
/// (dailies, then date refs), allocates a `CalendarItem` per daily, per date
/// ref and per due task, then sorts the result. `calendarDayMarks` walks
/// `calendar` again, and `notes` itself allocates and sorts the whole vault on
/// every access.
///
/// None of that is a problem once per index. It was a problem because it ran
/// inside the main shell `build()` (`app_mobile.dart`), guarded only by "a
/// daily note is open" — the state the app launches in — so it re-ran on every
/// autosave, every sync tick and every tab tap, at 20-40 ms a time on a
/// 6,200-note vault.
///
/// This measures the getter itself, so it stays honest about the cost the
/// controller is now paying once instead of per frame.
void main() {
  VaultIndex bigIndex({int notes = 6000}) {
    final byPath = <String, NoteRef>{};
    final tasks = <TaskRef>[];
    for (var i = 0; i < notes; i++) {
      final day = '2026-%02d-%02d'
          .replaceFirst('%02d', ((i % 12) + 1).toString().padLeft(2, '0'))
          .replaceFirst('%02d', ((i % 28) + 1).toString().padLeft(2, '0'));
      final isDaily = i % 6 == 0;
      final path = isDaily
          ? 'daily/2026/${((i % 12) + 1).toString().padLeft(2, '0')}/$day.typ'
          : 'notes/n$i.typ';
      byPath[path] = NoteRef(
        id: 'n$i',
        path: path,
        title: 'Note $i',
        kind: isDaily ? 'daily' : 'note',
        date: isDaily ? day : null,
        outgoingLinks: const [],
        dateRefs: i % 5 == 0 ? [DateRef(date: day)] : const [],
      );
      if (i % 3 == 0) {
        tasks.add(
          TaskRef(
            id: 't$i',
            notePath: path,
            text: 'Task $i',
            status: 'todo',
            due: day,
          ),
        );
      }
    }
    return VaultIndex(
      notesByPath: byPath,
      backlinksByTarget: const {},
      tasks: tasks,
    );
  }

  test('calendar is expensive enough that it must not run per frame', () {
    final index = bigIndex();
    final watch = Stopwatch()..start();
    final first = index.calendar;
    watch.stop();
    expect(first, isNotEmpty);

    // Not an assertion on absolute speed — machines differ. The point is that
    // the getter recomputes: a second call does the whole thing again, which is
    // exactly what a per-frame caller was paying.
    final second = index.calendar;
    expect(
      identical(first, second),
      isFalse,
      reason: 'calendar is computed per call — callers must cache it',
    );
    // ignore: avoid_print
    print('calendar over ${index.notes.length} notes: '
        '${watch.elapsedMilliseconds}ms, ${first.length} items');
  });

  test('calendarDayMarks walks the calendar again', () {
    final index = bigIndex();
    final marks = index.calendarDayMarks;
    expect(marks.daily, isNotEmpty);
    expect(
      identical(index.calendarDayMarks.daily, marks.daily),
      isFalse,
      reason: 'day marks are recomputed per call too',
    );
  });
}
