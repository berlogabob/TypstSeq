import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/olt/olt_cache.dart';

void main() {
  test('OLT calendar includes approved bookings on their local start day', () {
    final start = DateTime.parse('2026-10-21T23:30:00Z').toLocal();
    final day =
        '${start.year.toString().padLeft(4, '0')}-${start.month.toString().padLeft(2, '0')}-${start.day.toString().padLeft(2, '0')}';
    final items = oltCalendarOnDay({
      'activities': [
        {
          'id': 1,
          'title': 'Approved booking',
          'status': 'approved',
          'starts_at': '2026-10-21T23:30:00Z',
          'ends_at': '2026-10-22T00:30:00Z',
          'place_ids': [5],
        },
        {
          'id': 2,
          'title': 'Requested booking',
          'status': 'requested',
          'starts_at': '2026-10-21T23:30:00Z',
        },
        {
          'id': 3,
          'title': 'Another day',
          'status': 'approved',
          'starts_at': '2026-10-20T23:30:00Z',
          'location_text': 'Remote',
        },
        {
          'id': 4,
          'title': 'Location fallback',
          'status': 'approved',
          'starts_at': '2026-10-21T23:30:00Z',
          'location_text': 'Studio B',
        },
      ],
      'places': [
        {'id': 5, 'name': 'Lab 5'},
      ],
    }, day);

    expect(items.map((item) => item.title), [
      'Approved booking',
      'Location fallback',
    ]);
    expect(items.first.date, day);
    expect(
      items.first.start,
      '${start.hour.toString().padLeft(2, '0')}:${start.minute.toString().padLeft(2, '0')}',
    );
    expect(items.first.detail, 'Lab 5');
    expect(items.first.source, 'openlabtwin');
    expect(items.last.detail, 'Studio B');
  });

  test('OLT incoming filters local day, status, and decided ids', () {
    final items = oltIncomingOnDay(
      {
        'activities': [
          {
            'id': 1,
            'title': 'Requested',
            'status': 'requested',
            'starts_at': '2026-10-21T23:30:00Z',
            'ends_at': '2026-10-22T00:30:00Z',
            'place_ids': [5],
          },
          {
            'id': 2,
            'title': 'Approved',
            'status': 'approved',
            'starts_at': '2026-10-21T09:00:00Z',
          },
          {
            'id': 3,
            'title': 'Other day',
            'status': 'requested',
            'starts_at': '2026-10-20T09:00:00Z',
          },
        ],
        'ideas': [
          {
            'id': 9,
            'body':
                'A sufficiently long body used as fallback title for an idea that continues past sixty characters',
            'created_at': '2026-10-21T12:00:00Z',
          },
        ],
        'places': [
          {'id': 5, 'name': 'Lab 5'},
        ],
      },
      {'olt-activity-3'},
      '2026-10-22',
    );
    expect(items.map((item) => item.id), ['olt-activity-1']);
    expect(items.single.properties['places'], 'Lab 5');

    final ideas = oltIncomingOnDay(
      {
        'ideas': [
          {
            'id': 9,
            'body':
                'A sufficiently long body used as fallback title for an idea that continues past sixty characters',
            'created_at': '2026-10-21T12:00:00Z',
          },
        ],
      },
      const {},
      '2026-10-21',
    );
    expect(
      ideas.single.title,
      'A sufficiently long body used as fallback title for an idea ',
    );
  });
}
