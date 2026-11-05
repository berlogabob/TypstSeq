import 'dart:convert';
import 'dart:io';
import 'package:tylog/olt/olt_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/olt/olt_cache.dart';
import 'support/temp_dir.dart';

void main() {
  test('pages every cached table until a short page', () async {
    final dir = await Directory.systemTemp.createTemp('olt_pages');
    addTearDown(() => deleteTempDir(dir));
    final client = OltClient(
      store: _Store(),
      request: (_, uri, _, _) async {
        final offset = int.parse(uri.queryParameters['offset'] ?? '0');
        final limit = int.parse(uri.queryParameters['limit'] ?? '1000');
        expect(uri.queryParameters['order'], isNotNull);
        return OltResponse(
          200,
          jsonEncode(
            List.generate(offset == 0 ? limit : 1, (i) => {'id': offset + i}),
          ),
        );
      },
    );
    await syncOltCache(client, dir);
    final cache = await loadOltCache(dir);
    expect(cache.length, 7);
    expect(cache.values.every((rows) => rows.length == 1001), isTrue);
  });

  test('signed out loads cached rows without making requests', () async {
    final dir = await Directory.systemTemp.createTemp('olt_signed_out');
    addTearDown(() => deleteTempDir(dir));
    await File('${dir.path}/places.json').writeAsString('[{"id":1}]');
    final client = OltClient(
      store: _EmptyStore(),
      request: (_, _, _, _) async => throw StateError('unexpected request'),
    );
    final snapshot = await refreshOltCache(client, dir);
    expect(snapshot.cache['places'], hasLength(1));
    expect(snapshot.signedOut, isTrue);
  });

  test(
    'failed refresh persists error and last success while keeping rows',
    () async {
      final dir = await Directory.systemTemp.createTemp('olt_error');
      addTearDown(() => deleteTempDir(dir));
      var fail = false;
      final client = OltClient(
        store: _Store(),
        request: (_, _, _, _) async => fail
            ? const OltResponse(500, '{"message":"offline"}')
            : const OltResponse(200, '[{"id":1}]'),
      );
      await refreshOltCache(client, dir);
      fail = true;
      final result = await refreshOltCache(client, dir);
      final meta = await loadOltCacheMeta(dir);
      expect(result.cache['places'], hasLength(1));
      expect(meta.lastSuccess, isNotNull);
      expect(meta.error, contains('offline'));
      expect(meta.failedAt, isNotNull);
    },
  );

  test('403 keeps the entire previous cache', () async {
    final dir = await Directory.systemTemp.createTemp('olt_cache_test');
    addTearDown(() => deleteTempDir(dir));
    await File('${dir.path}/places.json').writeAsString(
      jsonEncode([
        {'id': 1},
      ]),
    );
    await File('${dir.path}/assets.json').writeAsString(
      jsonEncode([
        {'tag': 'old'},
      ]),
    );
    final client = OltClient(
      store: _Store(),
      request: (_, uri, _, _) async => uri.path.endsWith('/assets')
          ? const OltResponse(403, '{}')
          : const OltResponse(200, '[]'),
    );
    await expectLater(
      syncOltCache(client, dir),
      throwsA(isA<OltSignInNeeded>()),
    );
    final cache = await loadOltCache(dir);
    expect(cache['places'], [
      {'id': 1},
    ]);
    expect(cache['assets'], [
      {'tag': 'old'},
    ]);
  });

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
            'created_at': '2026-10-19T12:00:00Z',
          },
        ],
        'places': [
          {'id': 5, 'name': 'Lab 5'},
        ],
      },
      {'olt-activity-3'},
      // The local day of activity 1 (2026-10-22 in Lisbon, 2026-10-21 on UTC CI).
      _localDay('2026-10-21T23:30:00Z'),
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

  test('pending mode lists future requests and all new ideas on today', () {
    final cache = <String, List>{
      'activities': [
        {
          'id': 1,
          'title': 'Next week',
          'status': 'requested',
          'starts_at': '2026-11-10T10:00:00Z',
        },
        {
          'id': 2,
          'title': 'Past',
          'status': 'requested',
          'starts_at': '2026-10-01T10:00:00Z',
        },
      ],
      'ideas': [
        {'id': 9, 'body': 'Old idea', 'created_at': '2026-10-01T12:00:00Z'},
      ],
    };
    expect(oltIncomingOnDay(cache, {}, '2026-11-03'), isEmpty);
    final items = oltIncomingOnDay(cache, {}, '2026-11-03', pending: true);
    expect(items.map((item) => item.id), ['olt-activity-1', 'olt-idea-9']);
    expect(items.first.date, '2026-11-10');
  });
}

String _localDay(String utc) {
  final local = DateTime.parse(utc).toLocal();
  return '${local.year}-${local.month.toString().padLeft(2, '0')}-'
      '${local.day.toString().padLeft(2, '0')}';
}

class _Store implements OltSessionStore {
  @override
  Future<String?> read() async =>
      '{"email":"a@example.com","access":"a","refresh":"r","expiresAt":"2030-01-01T00:00:00.000"}';
  @override
  Future<void> write(String value) async {}
  @override
  Future<void> delete() async {}
}

class _EmptyStore implements OltSessionStore {
  @override
  Future<String?> read() async => null;
  @override
  Future<void> write(String value) async {}
  @override
  Future<void> delete() async {}
}
