import 'dart:convert';

import 'package:tylog_core/tylog_core.dart';

enum ReviewQueueType {
  mentions('Enrich mentions'),
  audio('Tasks and dates'),
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
    if (issue is! Map || issue['path'] is! String || issue['code'] is! String) {
      continue;
    }
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
        !path.endsWith('.typ')) {
      continue;
    }
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
  Iterable<Decision> decisions, {
  int offset = 0,
  int limit = 20,
  ActionableSidecarSummary? summary,
}) async {
  if (summary != null) {
    return summary.ocr(
      storage,
      mounts,
      decisions,
      offset: offset,
      limit: limit,
    );
  }
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
        if (manifest['template_id'] is String) {
          template = manifest['template_id'] as String;
        }
        if (manifest['created'] is String) {
          created = manifest['created'] as String;
        }
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
              fields is! Map) {
            continue;
          }
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
  return _page(result, offset, limit);
}

/// An Incoming "Add task" / "Add to agenda" item from an audio or screenshot
/// sidecar; [source] is the Decision source it is recorded under.
class AudioProposal {
  const AudioProposal(
    this.id,
    this.note,
    this.text,
    this.kind,
    this.date, {
    this.source = 'audio',
    this.time,
    this.place,
    String? title,
  }) : title = title ?? text;
  final String id, note, text, kind, source;
  final String? date, time, place;

  /// Event title without the time/place suffix in [text].
  final String title;
}

/// Caches parsed actionable sidecars by provider identity and file metadata.
/// Each changed input is read through a bounded stream to keep a corrupt or
/// unexpectedly large sidecar from monopolizing the Incoming refresh.
class ActionableSidecarSummary {
  static const _maxSidecarBytes = 1024 * 1024;
  final _files = <(Object, String), _CachedSidecar>{};

  Future<List<AudioProposal>> audio(
    VaultStorage storage,
    Iterable<Decision> decisions, {
    int offset = 0,
    int limit = 20,
  }) async {
    final rows = <AudioProposal>[];
    for (final (folder, source, prefix) in _actionSources) {
      try {
        for (final file in await storage.list(path: folder)) {
          if (file.isDirectory || !file.path.endsWith('.json')) continue;
          final cached = await _read(
            storage,
            file,
            () => <AudioProposal>[],
            parse: (text) =>
                _parseAudio(text, source: source, notePrefix: prefix),
          );
          rows.addAll(cached.audio);
        }
      } catch (_) {}
    }
    final decided = {
      for (final (_, source, _) in _actionSources)
        ..._decided(decisions, source).map((id) => (source, id)),
    };
    return _page(
      rows.where((row) => !decided.contains((row.source, row.id))).toList(),
      offset,
      limit,
    );
  }

  Future<List<OcrReviewRow>> ocr(
    VaultStorage storage,
    Iterable<String> mounts,
    Iterable<Decision> decisions, {
    int offset = 0,
    int limit = 20,
  }) async {
    final rows = <OcrReviewRow>[];
    for (final mount in mounts) {
      try {
        final root = 'ext/$mount';
        final manifest = await storage.stat('$root/manifest.json');
        final manifestText = manifest == null
            ? ''
            : await _readTextBounded(storage, manifest.path);
        var template = mount;
        var created = '';
        try {
          final data = jsonDecode(manifestText) as Map;
          if (data['template_id'] is String) {
            template = data['template_id'] as String;
          }
          if (data['created'] is String) created = data['created'] as String;
        } catch (_) {}
        final file = await storage.stat('$root/rows.jsonl');
        if (file == null || file.isDirectory) continue;
        final cached = await _read(
          storage,
          file,
          () => <OcrReviewRow>[],
          parse: (text) => _parseOcr(text, mount, template, created),
        );
        rows.addAll(cached.ocr);
      } catch (_) {}
    }
    final decided = _decided(decisions, 'ocr');
    return _page(
      rows.where((row) => !decided.contains(row.id)).toList(),
      offset,
      limit,
    );
  }

  Set<String> _decided(Iterable<Decision> decisions, String source) => decisions
      .where(
        (d) =>
            d.source == source &&
            (d.action == 'accepted' || d.action == 'rejected'),
      )
      .map((d) => d.item)
      .toSet();

  Future<_CachedSidecar> _read<T>(
    VaultStorage storage,
    VaultStorageEntry file,
    List<T> Function() empty, {
    List<T> Function(String text)? parse,
  }) async {
    final key = (storage.syncIdentity, file.path);
    final old = _files[key];
    final cacheable = file.size != null && file.modified != null;
    if (cacheable &&
        old != null &&
        old.size == file.size &&
        old.modified == file.modified) {
      return old;
    }
    final text = await _readTextBounded(storage, file.path);
    final parsed = parse == null
        ? (file.path.endsWith('.json') ? _parseAudio(text) : empty())
        : parse(text);
    final value = _CachedSidecar(
      file.size,
      file.modified,
      audio: parsed is List<AudioProposal> ? parsed : const [],
      ocr: parsed is List<OcrReviewRow> ? parsed : const [],
    );
    if (cacheable) {
      _files[key] = value;
    } else {
      _files.remove(key);
    }
    return value;
  }
}

class _CachedSidecar {
  const _CachedSidecar(
    this.size,
    this.modified, {
    this.audio = const [],
    this.ocr = const [],
  });
  final int? size;
  final DateTime? modified;
  final List<AudioProposal> audio;
  final List<OcrReviewRow> ocr;
}

Future<String> _readTextBounded(VaultStorage storage, String path) async {
  final stream = storage.openRead(
    path,
    0,
    ActionableSidecarSummary._maxSidecarBytes,
  );
  if (stream == null) {
    if ((await storage.stat(path))?.size case final size?
        when size > ActionableSidecarSummary._maxSidecarBytes) {
      return '';
    }
    final bytes = await storage.readBytes(path);
    return utf8.decode(
      bytes.take(ActionableSidecarSummary._maxSidecarBytes).toList(),
      allowMalformed: true,
    );
  }
  final bytes = <int>[];
  await for (final chunk in stream) {
    final remaining = ActionableSidecarSummary._maxSidecarBytes - bytes.length;
    if (remaining <= 0) break;
    bytes.addAll(chunk.take(remaining));
    if (chunk.length > remaining) break;
  }
  return utf8.decode(bytes, allowMalformed: true);
}

/// Sidecar folders with Incoming "Add task" / "Add to agenda" items, the
/// Decision source for each, and the folder their notes must live in.
const _actionSources = [
  ('_system/enrich/audio', 'audio', 'notes/'),
  ('_system/enrich/actions', 'screenshot', 'screenshots/'),
];

List<AudioProposal> _parseAudio(
  String text, {
  String source = 'audio',
  String notePrefix = 'notes/',
}) {
  final date = RegExp(r'^\d{4}-\d{2}-\d{2}$');
  final time = RegExp(r'^\d{2}:\d{2}$');
  try {
    final data = jsonDecode(text) as Map;
    final note = data['note'];
    if (note is! String ||
        !note.startsWith(notePrefix) ||
        !note.endsWith('.typ')) {
      return [];
    }
    return [
      for (final item in data['items'] as List)
        if (item is Map &&
            item['id'] is String &&
            item['text'] is String &&
            (item['text'] as String).trim().isNotEmpty)
          AudioProposal(
            item['id'] as String,
            note,
            item['text'] as String,
            item['kind'] == 'agenda' && item['date'] is String
                ? 'agenda'
                : 'task',
            item['date'] is String && date.hasMatch(item['date'] as String)
                ? item['date'] as String
                : null,
            source: source,
            title:
                item['title'] is String &&
                    (item['title'] as String).trim().isNotEmpty
                ? (item['title'] as String).trim()
                : null,
            time:
                item['time'] is String && time.hasMatch(item['time'] as String)
                ? item['time'] as String
                : null,
            place:
                item['place'] is String &&
                    (item['place'] as String).trim().isNotEmpty
                ? (item['place'] as String).trim()
                : null,
          ),
    ];
  } catch (_) {
    return [];
  }
}

List<OcrReviewRow> _parseOcr(
  String text,
  String mount,
  String template,
  String created,
) {
  final rows = <OcrReviewRow>[];
  for (final line in const LineSplitter().convert(text)) {
    try {
      final row = jsonDecode(line) as Map;
      final hash = row['source_photo_hash'];
      final fields = row['fields'];
      if (row['review'] != true ||
          hash is! String ||
          hash.isEmpty ||
          fields is! Map) {
        continue;
      }
      rows.add(
        OcrReviewRow(
          'ocr:$mount:$hash',
          template,
          created,
          fields.entries
              .map(
                (e) =>
                    '${e.key}: ${e.value is Map ? e.value['value'] : e.value}',
              )
              .join('\n'),
        ),
      );
    } catch (_) {}
  }
  return rows;
}

Future<List<AudioProposal>> loadAudioProposals(
  VaultStorage storage,
  Iterable<Decision> decisions, {
  int offset = 0,
  int limit = 20,
  ActionableSidecarSummary? summary,
}) async {
  if (summary != null) {
    return summary.audio(storage, decisions, offset: offset, limit: limit);
  }
  return ActionableSidecarSummary().audio(
    storage,
    decisions,
    offset: offset,
    limit: limit,
  );
}

List<T> _page<T>(List<T> rows, int offset, int limit) {
  final start = offset.clamp(0, rows.length);
  final end = (start + limit.clamp(1, 100)).clamp(start, rows.length);
  return rows.sublist(start, end);
}
