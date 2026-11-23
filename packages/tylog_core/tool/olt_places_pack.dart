// Builds the IADE places pack from OpenLabTwin exports: every row of the
// `places` table, plus every location named in the schedule (`activities`).
// Each note points back at the rows it came from.
//
//   dart run tool/olt_places_pack.dart places.json activities.json out.tylogpack
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:tylog_core/tylog_core.dart';

const _id = 'iade-techlab';

/// Schedule locations are free text: a name is a room, a lab or a building by
/// its wording. Anything else (a link, an event name) is not a place.
String? _kindOf(String name) {
  final lower = name.toLowerCase();
  if (RegExp(r'^(sala|auditório|estúdio)\b').hasMatch(lower) ||
      lower.contains('estúdio')) {
    return 'room';
  }
  if (lower.endsWith('lab') || lower == 'fábrica') return 'lab';
  if (lower.startsWith('edifício')) return 'place';
  return null;
}

String _slug(String name) => name
    .toLowerCase()
    .replaceAll(RegExp(r'[áàâã]'), 'a')
    .replaceAll(RegExp(r'[éê]'), 'e')
    .replaceAll('í', 'i')
    .replaceAll(RegExp(r'[óôõ]'), 'o')
    .replaceAll('ú', 'u')
    .replaceAll('ç', 'c')
    .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
    .replaceAll(RegExp(r'^-|-$'), '');

void main(List<String> args) {
  if (args.length != 3) {
    stderr.writeln('usage: olt_places_pack places.json activities.json out');
    exit(64);
  }
  final places = (jsonDecode(File(args[0]).readAsStringSync()) as List)
      .cast<Map>();
  final activities = (jsonDecode(File(args[1]).readAsStringSync()) as List)
      .cast<Map>();
  final notes = <String, NoteMetadataDraft>{};
  final taken = <String>{};
  for (final place in places) {
    final id = 'olt-place-${place['id']}';
    taken.add('${place['name']}'.toLowerCase());
    notes[id] = NoteMetadataDraft(
      id: id,
      title: '${place['name']}',
      kind: place['kind'] == 'storage' ? 'storage' : 'room',
      properties: {
        'part_of': [
          place['parent_id'] == null
              ? 'IADE'
              : 'olt-place-${place['parent_id']}',
        ],
        'code': ?place['code'],
        'tier': ?place['tier'],
        'source': 'openlabtwin',
        'evidence': 'openlabtwin:places/${place['id']}',
      },
    );
  }
  final seen = <String, List<Object?>>{};
  for (final activity in activities) {
    final name = '${activity['location_text'] ?? ''}'.trim();
    if (name.isNotEmpty) (seen[name] ??= []).add(activity['id']);
  }
  final skipped = <String>[];
  for (final entry in seen.entries) {
    final kind = _kindOf(entry.key);
    if (kind == null || taken.contains(entry.key.toLowerCase())) {
      skipped.add(entry.key);
      continue;
    }
    final id = 'iade-${_slug(entry.key)}';
    notes[id] = NoteMetadataDraft(
      id: id,
      title: entry.key,
      kind: kind,
      properties: {
        'part_of': ['IADE'],
        'source': 'openlabtwin',
        'evidence': 'openlabtwin:activities/${entry.value.join(',')}',
      },
    );
  }

  final files = <String, List<int>>{
    'ontology.json': File('../../docs/ontology/techlab.json').readAsBytesSync(),
    for (final entry in notes.entries)
      'notes/${entry.key}.typ': utf8.encode(replaceNoteHeader('', entry.value)),
  };
  final manifest = utf8.encode(
    const JsonEncoder.withIndent('  ').convert({
      'schema': 1,
      'id': _id,
      'name': 'IADE TechLAB places',
      'version': '0.1.0',
      'files': [
        for (final entry in files.entries)
          {'path': entry.key, 'sha256': sha256.convert(entry.value).toString()},
      ],
    }),
  );
  final archive = Archive()
    ..addFile(ArchiveFile('manifest.json', manifest.length, manifest));
  files.forEach(
    (path, bytes) => archive.addFile(ArchiveFile(path, bytes.length, bytes)),
  );
  File(args[2]).writeAsBytesSync(ZipEncoder().encode(archive));
  for (final note in notes.values) {
    stdout.writeln('${note.kind}\t${note.title}');
  }
  stdout.writeln('${notes.length} notes; not places: ${skipped.join(' | ')}');
}
