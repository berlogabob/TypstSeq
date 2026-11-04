import 'dart:convert';

import 'package:tylog_core/tylog_core.dart';

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
