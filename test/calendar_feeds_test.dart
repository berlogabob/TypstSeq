import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:crypto/crypto.dart';
import 'package:tylog/calendar_feeds.dart';
import 'package:tylog/scanner.dart';
import 'package:tylog/vault.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final body = jsonEncode([
    {
      'date': '2026-10-08',
      'start': '19:00',
      'end': '21:00',
      'course': 'Ética',
      'groups': ['MCIA003N01'],
      'teachers': ['Ana'],
      'rooms': ['020'],
      'programmes': ['MCIA'],
      'degrees': ['Master'],
    },
  ]);
  test(
    'event mentions match title, course and date and prioritize edited day',
    () {
      FeedEvent event(
        String id,
        String date,
        String title, {
        String course = '',
      }) => FeedEvent(id, title, date, {
        'course': course,
        'event_type': 'lab',
        'start': '19:00',
      });
      final events = [
        event('past', '2026-10-05', 'Ética'),
        event('future', '2026-10-08', 'Ética'),
        event('edited', '2026-10-09', 'Open lab', course: 'Ética'),
        event('old', '2026-09-28', 'Ética'),
        event('far', '2026-10-21', 'Ética'),
      ];
      List<String> ids(String q) => searchFeedEvents(
        events,
        q,
        today: DateTime(2026, 10, 6),
        editedDay: '2026-10-09',
      ).map((e) => e.id).toList();
      expect(ids('Éti'), ['edited', 'future', 'past']);
      expect(ids('lab 8 Oct'), ['future']);
      expect(ids('2026-10-09'), ['edited']);
    },
  );
  test('classes filter and stable identity', () {
    final event = parseTimetable(body).single;
    expect(
      event.id,
      sha1
          .convert(utf8.encode('2026-10-08|19:00|Ética|MCIA003N01'))
          .toString()
          .substring(0, 16),
    );
    expect(parseTimetable(body, group: 'other'), isEmpty);
    expect(parseTimetable(body, programme: 'other'), isEmpty);
    expect(parseTimetable(body, degree: 'Master'), hasLength(1));
    expect(event.path, 'events/2026/10/${event.id}.typ');
  });
  test('ICS unfolding, escapes, TZID and UTC', () {
    final events = parseLabCalendar(
      'BEGIN:VCALENDAR\r\nBEGIN:VEVENT\r\nUID:lab/a\r\nDTSTART;TZID=Europe/Lisbon:20261008T190000\r\nDTEND:20261008T200000Z\r\nSUMMARY:Open\r\n lab\r\nLOCATION:Room\\, 2\r\nDESCRIPTION:One\\nTwo\r\nEND:VEVENT\r\nEND:VCALENDAR',
    );
    final event = events.single;
    expect(event.id, 'lab/a');
    expect(event.title, 'Openlab');
    expect(
      DateTime.parse(event.properties['start'] as String).toUtc(),
      DateTime.utc(2026, 10, 8, 18),
    );
    expect(
      DateTime.parse(event.properties['end'] as String).toUtc(),
      DateTime.utc(2026, 10, 8, 20),
    );
    expect(event.properties['description'], 'One\nTwo');
    expect(event.path, contains('lab%2Fa.typ'));
  });
  testWidgets('event creation reuses page and preserves written body', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final root = await Directory.systemTemp.createTemp('tylog_events_');
      try {
        final vault = Vault(root);
        await vault.ensureCreated();
        final event = parseTimetable(body).single;
        final metadata = NoteMetadataDraft(
          id: event.id,
          title: event.title,
          kind: 'event',
          date: event.date,
          properties: event.properties,
        );
        final path = await vault.page(
          event.title,
          kind: 'event',
          eventPath: event.path,
          metadata: metadata,
        );
        final original = await vault.storage.readText(path);
        await vault.storage.writeText(path, '$original\nMy notes\n');
        expect(
          await vault.page(
            event.title,
            kind: 'event',
            eventPath: event.path,
            metadata: metadata,
          ),
          path,
        );
        final source = await vault.storage.readText(path);
        expect(source, contains('My notes'));
        expect(source, contains('kind: "event"'));
        expect(
          replaceNoteProperty(source, 'source_status', 'cancelled'),
          contains('My notes'),
        );
      } finally {
        await root.delete(recursive: true);
      }
    });
  });
}
