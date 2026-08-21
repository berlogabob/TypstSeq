import 'dart:io';

import 'package:test/test.dart';
import 'package:tylog_core/models.dart';
import 'package:tylog_core/scanner.dart';
import 'package:tylog_core/storage.dart';

/// A daily note whose header omits `date:` — created by an older build, or by
/// hand. Five such notes existed on the real vault, and every one of them
/// was invisible on the calendar and sorted *above* today in the journal feed
/// (the feed's key falls back to the path, and `daily/...` sorts above
/// `2026-...` descending, so today ended up six entries down).
const _noDate = '''#import "/_system/tylog.typ" as tylog
#show: tylog.note.with(
  id: "2026-08-17",
  title: "2026-08-17",
  kind: "daily",
)
= 2026-08-17
''';

const _withDate = '''#import "/_system/tylog.typ" as tylog
#show: tylog.note.with(
  id: "2026-08-21",
  title: "2026-08-21",
  kind: "daily",
  date: "2026-08-21",
)
= 2026-08-21
''';

void main() {
  late Directory root;
  late LocalVaultStorage storage;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('tylog-daily-date');
    storage = LocalVaultStorage(root);
  });

  tearDown(() => root.delete(recursive: true));

  test('a daily note gets its date from the path when the header omits it',
      () async {
    await storage.writeText('daily/2026/08/2026-08-17.typ', _noDate);
    await storage.writeText('daily/2026/08/2026-08-21.typ', _withDate);

    final index = await scanVaultStorage(storage);
    final byName = {
      for (final note in index.notes) note.path.split('/').last: note,
    };

    expect(byName['2026-08-17.typ']!.date, '2026-08-17');
    expect(byName['2026-08-21.typ']!.date, '2026-08-21');

    // Both days therefore reach the calendar.
    expect(
      index.calendar.map((item) => item.date),
      containsAll(['2026-08-17', '2026-08-21']),
    );
  });

  // An index cached by an earlier build still carries date: null. Repairing
  // those by re-deriving would mean a version bump, i.e. every device
  // recompiling its whole vault — so the read paths derive the day instead.
  test('a cached daily entry with no date still reaches the calendar', () {
    final index = VaultIndex(
      notesByPath: {
        'daily/2026/08/2026-08-17.typ': const NoteRef(
          id: '2026-08-17',
          path: 'daily/2026/08/2026-08-17.typ',
          title: '2026-08-17',
          kind: 'daily',
          outgoingLinks: [],
        ),
      },
      backlinksByTarget: const {},
      tasks: const [],
    );

    expect(index.notes.single.date, isNull);
    expect(dailyDayOf(index.notes.single), '2026-08-17');
    expect(index.calendar.map((item) => item.date), contains('2026-08-17'));
    expect(index.calendarDayMarks.daily, contains('2026-08-17'));
  });

  test('an explicit date always wins over the path', () async {
    // Deliberate mismatch: the header is the author's intent.
    await storage.writeText(
      'daily/2026/08/2026-08-17.typ',
      _withDate.replaceAll('2026-08-21', '2026-08-21'),
    );
    final index = await scanVaultStorage(storage);
    expect(index.notes.single.date, '2026-08-21');
  });

  test('a non-daily note is not given a date from its path', () async {
    await storage.writeText(
      'notes/2026-08-17 meeting.typ',
      '#show: tylog.note.with(id: "m", title: "Meeting", kind: "note")\n',
    );
    final index = await scanVaultStorage(storage);
    expect(index.notes.single.date, isNull);
  });
}
