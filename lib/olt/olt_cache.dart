import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models.dart';
import 'olt_client.dart';

Future<Directory> oltCacheDirectory() async =>
    Directory('${(await getApplicationSupportDirectory()).path}/olt');

Future<void> syncOltCache(OltClient client, Directory dir) async {
  await dir.create(recursive: true);
  final today = DateTime.now().subtract(const Duration(days: 7));
  final from = DateTime(today.year, today.month, today.day).toUtc();
  final tables = <String, String>{
    'activities':
        'select=id,title,layer,kind,place_ids,location_text,starts_at,ends_at,status,requester_display&starts_at=gte.${Uri.encodeQueryComponent(from.toIso8601String())}&order=starts_at',
    'ideas':
        'select=id,body,status,created_at,ai_title,ai_summary&status=eq.new',
    'places': 'select=id,name,kind',
  };
  for (final entry in tables.entries) {
    final rows = await client.get(entry.key, entry.value);
    await File('${dir.path}/${entry.key}.json').writeAsString(jsonEncode(rows));
  }
}

Future<Map<String, List>> loadOltCache(Directory dir) async {
  final result = <String, List>{};
  for (final table in ['activities', 'ideas', 'places']) {
    final file = File('${dir.path}/$table.json');
    if (!await file.exists()) continue;
    final rows = jsonDecode(await file.readAsString());
    if (rows is List) result[table] = rows;
  }
  return result;
}

Future<Set<String>> readDecidedOltIds(Directory dir) async {
  final file = File('${dir.path}/decided.json');
  if (!await file.exists()) return <String>{};
  try {
    return (jsonDecode(await file.readAsString()) as List)
        .cast<String>()
        .toSet();
  } catch (_) {
    return <String>{};
  }
}

Future<void> addDecidedOltId(Directory dir, String id) async {
  await dir.create(recursive: true);
  final decided = await readDecidedOltIds(dir)
    ..add(id);
  await File(
    '${dir.path}/decided.json',
  ).writeAsString(jsonEncode(decided.toList()));
}

List<NoteRef> oltIncomingOnDay(
  Map<String, List> cache,
  Set<String> decided,
  String day,
) {
  String? localDay(Object? value) {
    final date = DateTime.tryParse('$value')?.toLocal();
    if (date == null) return null;
    return '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  final places = {
    for (final row in cache['places'] ?? const [])
      '${row['id']}': '${row['name']}',
  };
  final result = <NoteRef>[];
  for (final row in cache['activities'] ?? const []) {
    if (row['status'] != 'requested' || localDay(row['starts_at']) != day) {
      continue;
    }
    final id = 'olt-activity-${row['id']}';
    if (decided.contains(id)) continue;
    final names = (row['place_ids'] as List? ?? const [])
        .map((value) => places['$value'])
        .whereType<String>()
        .toList();
    result.add(
      NoteRef(
        id: id,
        path: 'olt:activities/${row['id']}',
        title: '${row['title'] ?? ''}',
        kind: 'booking',
        date: day,
        outgoingLinks: const [],
        properties: {
          'source': 'openlabtwin',
          'starts_at': row['starts_at'],
          'ends_at': row['ends_at'],
          'places': names.join(', '),
        },
      ),
    );
  }
  for (final row in cache['ideas'] ?? const []) {
    if (localDay(row['created_at']) != day) continue;
    final id = 'olt-idea-${row['id']}';
    if (decided.contains(id)) continue;
    final body = '${row['body'] ?? ''}';
    result.add(
      NoteRef(
        id: id,
        path: 'olt:ideas/${row['id']}',
        title:
            row['ai_title'] as String? ??
            (body.length <= 60 ? body : body.substring(0, 60)),
        kind: 'idea',
        date: day,
        outgoingLinks: const [],
        properties: {'source': 'openlabtwin', 'summary': row['ai_summary']},
      ),
    );
  }
  return result;
}
