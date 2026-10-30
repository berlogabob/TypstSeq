import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/olt/olt_cache.dart';

void main() {
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
