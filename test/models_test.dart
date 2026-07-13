import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/models.dart';

void main() {
  test('calendarDayMarks separates journal days from reference-only days', () {
    const daily = NoteRef(
      id: '2026-07-10',
      path: 'daily/2026/07/2026-07-10.typ',
      title: '2026-07-10',
      kind: 'daily',
      date: '2026-07-10',
      outgoingLinks: [],
    );
    const mentioning = NoteRef(
      id: 'n1',
      path: 'notes/a.typ',
      title: 'A',
      outgoingLinks: [],
      dateRefs: [DateRef(date: '2026-07-12')],
    );
    const task = TaskRef(
      id: 't1',
      notePath: 'notes/a.typ',
      text: 'Ship it',
      due: '2026-07-15T09:00',
    );
    final index = VaultIndex(
      notesByPath: {daily.path: daily, mentioning.path: mentioning},
      backlinksByTarget: const {},
      tasks: const [task],
    );

    final marks = index.calendarDayMarks;
    expect(marks.daily, {'2026-07-10'});
    expect(marks.refs, {'2026-07-12', '2026-07-15'});
  });
}
