import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'models.dart';

const timetableUrl = 'https://berlogabob.github.io/iade-lab-schedule/all.json';
const labUrl = 'https://berlogabob.github.io/openlabtwin/calendar/lab.ics';

class FeedEvent {
  FeedEvent(this.id, this.title, this.date, this.properties);
  final String id, title, date;
  final Map<String, Object?> properties;
  String get path =>
      'events/${date.substring(0, 4)}/${date.substring(5, 7)}/${Uri.encodeComponent(id)}.typ';
  String get label {
    String time(Object? value) {
      final text = value?.toString() ?? '';
      return text.contains('T') ? text.split('T').last.substring(0, 5) : text;
    }

    return '$title · ${time(properties['start'])}–${time(properties['end'])}${properties['rooms'] == '' ? '' : ' · ${properties['rooms']}'}';
  }

  CalendarItem get item => CalendarItem(
    date: date,
    kind: CalendarItemKind.dateRef,
    title: label,
    notePath: path,
  );
}

List<FeedEvent> parseTimetable(
  String body, {
  String group = 'MCIA003N01',
  String programme = '',
  String degree = '',
}) {
  String value(Object? v) => v is List ? v.join(', ') : v?.toString() ?? '';
  bool includes(Object? v, String filter) =>
      filter.isEmpty ||
      (v is List ? v.map((e) => e.toString()).contains(filter) : v == filter);
  return [
    for (final row in jsonDecode(body) as List)
      if (includes(row['groups'], group) &&
          includes(row['programmes'], programme) &&
          includes(row['degrees'], degree))
        FeedEvent(
          sha1
              .convert(
                utf8.encode(
                  '${row['date']}|${row['start']}|${row['course']}|$group',
                ),
              )
              .toString()
              .substring(0, 16),
          row['course'] as String,
          row['date'] as String,
          {
            'event_type': 'class',
            'start': row['start'],
            'end': row['end'],
            'course': row['course'],
            'teachers': value(row['teachers']),
            'rooms': value(row['rooms']),
            'source_status': 'current',
          },
        ),
  ];
}

List<FeedEvent> parseLabCalendar(String body) {
  if (!body.contains('BEGIN:VCALENDAR') && !body.contains('BEGIN:VEVENT')) {
    throw const FormatException('Invalid ICS calendar');
  }
  tzdata.initializeTimeZones();
  final result = <FeedEvent>[];
  var fields = <String, String>{};
  var zones = <String, String>{};
  DateTime instant(String key) {
    final raw = fields[key]!;
    final match = RegExp(
      r'^(\d{4})(\d{2})(\d{2})(?:T(\d{2})(\d{2})(\d{2}))?(Z)?$',
    ).firstMatch(raw);
    if (match == null) throw FormatException('Invalid ICS date', raw);
    final parts = [for (var i = 1; i <= 6; i++) int.parse(match[i] ?? '0')];
    if (match[7] != null) {
      return DateTime.utc(
        parts[0],
        parts[1],
        parts[2],
        parts[3],
        parts[4],
        parts[5],
      ).toLocal();
    }
    final zone = zones[key];
    if (zone != null) {
      return tz.TZDateTime(
        tz.getLocation(zone),
        parts[0],
        parts[1],
        parts[2],
        parts[3],
        parts[4],
        parts[5],
      ).toLocal();
    }
    return DateTime(parts[0], parts[1], parts[2], parts[3], parts[4], parts[5]);
  }

  for (final line
      in body
          .replaceAll('\r\n', '\n')
          .replaceAll(RegExp(r'\n[ \t]'), '')
          .split('\n')) {
    if (line == 'BEGIN:VEVENT') {
      fields = {};
      zones = {};
      continue;
    }
    if (line == 'END:VEVENT') {
      if (fields['UID'] == null ||
          fields['DTSTART'] == null ||
          fields['SUMMARY'] == null) {
        throw const FormatException('Incomplete VEVENT');
      }
      final start = instant('DTSTART');
      final end = fields.containsKey('DTEND') ? instant('DTEND') : start;
      result.add(
        FeedEvent(
          fields['UID']!,
          fields['SUMMARY']!,
          start.toIso8601String().substring(0, 10),
          {
            'event_type': 'lab',
            'start': start.toIso8601String(),
            'end': end.toIso8601String(),
            'course': '',
            'teachers': '',
            'rooms': fields['LOCATION'] ?? '',
            'description': fields['DESCRIPTION'] ?? '',
            'source_status': 'current',
          },
        ),
      );
      continue;
    }
    final colon = line.indexOf(':');
    if (colon < 0) continue;
    final key = line.substring(0, colon).split(';').first;
    fields[key] = line
        .substring(colon + 1)
        .replaceAll(r'\n', '\n')
        .replaceAll(r'\N', '\n')
        .replaceAll(r'\,', ',')
        .replaceAll(r'\;', ';')
        .replaceAll(r'\\', '\\');
    final zone = RegExp(
      r';TZID="?([^;":]+)',
    ).firstMatch(line.substring(0, colon));
    if (zone != null) zones[key] = zone[1]!;
  }
  return result;
}

Future<String> fetchCalendarBody(String url) async {
  final uri = Uri.parse(url);
  if (uri.scheme != 'https' || uri.host.isEmpty) {
    throw const FormatException('Calendar URL must use HTTPS');
  }
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
  try {
    final request = await client
        .getUrl(uri)
        .timeout(const Duration(seconds: 20));
    final response = await request.close().timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) {
      throw HttpException('Calendar HTTP ${response.statusCode}');
    }
    return await response
        .transform(utf8.decoder)
        .join()
        .timeout(const Duration(seconds: 20));
  } finally {
    client.close(force: true);
  }
}
