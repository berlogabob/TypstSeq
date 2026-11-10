import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/calendar_feeds.dart';
import 'package:tylog/models.dart';

NoteRef _event(String? date, Map<String, Object?> properties) => NoteRef(
  id: 'e',
  path: 'events/2026/11/e.typ',
  title: 'Jantar & co',
  kind: 'event',
  date: date,
  outgoingLinks: const [],
  properties: properties,
);

void main() {
  test('timed event opens a one-hour Google Calendar template', () {
    final url = Uri.parse(
      googleCalendarTemplateUrl(
        _event('2026-11-12', {'start': '2026-11-12T20:30', 'place': 'Tomar'}),
      )!,
    );
    expect(url.host, 'calendar.google.com');
    expect(url.queryParameters['action'], 'TEMPLATE');
    expect(url.queryParameters['text'], 'Jantar & co');
    expect(url.queryParameters['dates'], '20261112T203000/20261112T213000');
    expect(url.queryParameters['location'], 'Tomar');
  });

  test('end time and all-day events', () {
    expect(
      Uri.parse(
        googleCalendarTemplateUrl(
          _event('2026-11-12', {
            'start': '2026-11-12T09:00',
            'end': '2026-11-12T10:15',
          }),
        )!,
      ).queryParameters['dates'],
      '20261112T090000/20261112T101500',
    );
    expect(
      Uri.parse(
        googleCalendarTemplateUrl(_event('2026-12-31', const {}))!,
      ).queryParameters['dates'],
      '20261231/20270101',
    );
    expect(googleCalendarTemplateUrl(_event(null, const {})), isNull);
  });
}
