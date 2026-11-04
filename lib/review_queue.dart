import 'dart:convert';

import 'package:tylog_core/tylog_core.dart';

enum ReviewQueueType {
  mentions('Enrich mentions'),
  audio('Audio proposals'),
  ocr('OCR rows'),
  bookings('OpenLabTwin bookings'),
  health('Vault health');

  const ReviewQueueType(this.label);
  final String label;
}

const reviewQueueTypes = ReviewQueueType.values;

class HealthFinding {
  const HealthFinding(this.path, this.code);
  final String path, code;
}

Future<List<HealthFinding>> loadHealthFindings(VaultStorage storage) async {
  const root = '_system/health';
  if (!await storage.exists(root)) return [];
  final reports =
      (await storage.list(path: root))
          .where(
            (file) =>
                !file.isDirectory &&
                RegExp(
                  r'^_system/health/\d{4}-\d{2}-\d{2}\.json$',
                ).hasMatch(file.path),
          )
          .map((file) => file.path)
          .toList()
        ..sort();
  if (reports.isEmpty) return [];
  final report = jsonDecode(await storage.readText(reports.last)) as Map;
  final findings = <HealthFinding>[];
  for (final issue in report['issues'] as List) {
    if (issue is! Map || issue['path'] is! String || issue['code'] is! String)
      continue;
    final path = issue['path'] as String;
    final parts = path.split('/');
    if (parts.length < 2 ||
        parts.any(
          (part) =>
              part.isEmpty ||
              part == '.' ||
              part == '..' ||
              part.contains('\\'),
        ) ||
        !const {
          'daily',
          'notes',
          'projects',
          'articles',
          'screenshots',
          'ext',
        }.contains(parts.first) ||
        !path.endsWith('.typ'))
      continue;
    findings.add(HealthFinding(path, issue['code'] as String));
  }
  return findings;
}

class OcrReviewRow {
  const OcrReviewRow(this.id, this.dataset, this.date, this.fields);
  final String id, dataset, date, fields;
}

Future<List<OcrReviewRow>> loadOcrReviewRows(
  VaultStorage storage,
  Iterable<String> mounts,
  Iterable<Decision> decisions,
) async {
  final decided = decisions
      .where(
        (d) =>
            d.source == 'ocr' &&
            (d.action == 'accepted' || d.action == 'rejected'),
      )
      .map((d) => d.item)
      .toSet();
  final result = <OcrReviewRow>[];
  for (final mount in mounts) {
    final root = 'ext/$mount';
    try {
      var template = mount;
      var created = '';
      try {
        final manifest =
            jsonDecode(await storage.readText('$root/manifest.json')) as Map;
        if (manifest['template_id'] is String)
          template = manifest['template_id'] as String;
        if (manifest['created'] is String)
          created = manifest['created'] as String;
      } catch (_) {}
      final text = await storage.readText('$root/rows.jsonl');
      for (final line in const LineSplitter().convert(text)) {
        try {
          final row = jsonDecode(line) as Map;
          final hash = row['source_photo_hash'];
          final fields = row['fields'];
          if (row['review'] != true ||
              hash is! String ||
              hash.isEmpty ||
              fields is! Map)
            continue;
          final id = 'ocr:$mount:$hash';
          if (decided.contains(id)) continue;
          result.add(
            OcrReviewRow(
              id,
              template,
              created,
              fields.entries
                  .map((e) {
                    final field = e.value;
                    return '${e.key}: ${field is Map ? field['value'] : field}';
                  })
                  .join('\n'),
            ),
          );
        } catch (_) {}
      }
    } catch (_) {}
  }
  return result;
}

class AudioProposal {
  const AudioProposal(this.id, this.note, this.text, this.kind, this.date);
  final String id, note, text, kind;
  final String? date;
}

Future<List<AudioProposal>> loadAudioProposals(
  VaultStorage storage,
  Iterable<Decision> decisions,
) async {
  final decided = decisions
      .where(
        (d) =>
            d.source == 'audio' &&
            (d.action == 'accepted' || d.action == 'rejected'),
      )
      .map((d) => d.item)
      .toSet();
  final result = <AudioProposal>[];
  try {
    for (final file in await storage.list(path: '_system/enrich/audio')) {
      if (file.isDirectory || !file.path.endsWith('.json')) continue;
      try {
        final data = jsonDecode(await storage.readText(file.path)) as Map;
        final note = data['note'];
        if (note is! String ||
            !note.startsWith('notes/') ||
            !note.endsWith('.typ'))
          continue;
        for (final item in data['items'] as List) {
          if (item is! Map ||
              item['id'] is! String ||
              item['text'] is! String ||
              (item['text'] as String).trim().isEmpty ||
              decided.contains(item['id']))
            continue;
          final date = item['date'];
          result.add(
            AudioProposal(
              item['id'],
              note,
              item['text'],
              item['kind'] == 'agenda' && date is String ? 'agenda' : 'task',
              date is String && RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(date)
                  ? date
                  : null,
            ),
          );
        }
      } catch (_) {}
    }
  } catch (_) {}
  return result;
}
