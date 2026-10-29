import 'dart:convert';

import 'enrich.dart';
import 'models.dart';
import 'storage.dart';

const attentionStates = ['new', 'kept', 'acted', 'archived'];

String? attentionOf(NoteRef note) {
  final explicit = note.properties['attention'];
  if (attentionStates.contains(explicit)) return explicit as String;

  final status = note.properties['status'];
  switch (note.kind) {
    case 'screenshot':
      if (status == null || status == 'inbox') return 'new';
      if (['kept', 'acted', 'archived'].contains(status)) {
        return status as String;
      }
    case 'idea':
      if (status == null || status == 'new') return 'new';
      if (status == 'approved') return 'kept';
      if (status == 'archived') return 'archived';
    case 'audio':
      return 'new';
  }
  return null;
}

const decisionsDir = '_system/decisions';
const decisionActions = [
  'seen',
  'added-to-today',
  'scheduled',
  'accepted',
  'rejected',
  'dismissed',
  'ignored',
];

class Decision {
  const Decision({
    required this.at,
    required this.device,
    required this.item,
    required this.source,
    required this.action,
    this.target,
    this.context,
  });

  final String at;
  final String device;
  final String item;
  final String source;
  final String action;
  final String? target;
  final String? context;

  Map<String, Object?> toJson() => {
    'at': at,
    'device': device,
    'item': item,
    'source': source,
    'action': action,
    if (target != null) 'target': target,
    if (context != null) 'context': context,
  };

  static List<Decision> parseLog(String text) => [
    for (final line in const LineSplitter().convert(text)) ?_tryLine(line),
  ];

  static Decision? _tryLine(String line) {
    try {
      final json = jsonDecode(line) as Map;
      if (!decisionActions.contains(json['action'])) return null;
      return Decision(
        at: json['at'] as String,
        device: json['device'] as String,
        item: json['item'] as String,
        source: json['source'] as String,
        action: json['action'] as String,
        target: json['target'] as String?,
        context: json['context'] as String?,
      );
    } catch (_) {
      return null;
    }
  }
}

String encodeDecisions(List<Decision> rows) =>
    rows.map((row) => jsonEncode(row.toJson())).join('\n') +
    (rows.isEmpty ? '' : '\n');

Future<List<Decision>> loadDecisions(VaultStorage storage) async {
  final decisions = <Decision>[];
  try {
    for (final file in await storage.list(path: decisionsDir)) {
      if (file.isDirectory || !file.path.endsWith('.jsonl')) continue;
      decisions.addAll(Decision.parseLog(await storage.readText(file.path)));
    }
  } catch (_) {}
  for (final feedback in await loadEnrichFeedback(storage)) {
    decisions.add(
      Decision(
        at: feedback.at,
        device: '',
        item: feedback.note,
        source: 'enrich',
        action: feedback.accepted ? 'accepted' : 'rejected',
        target: feedback.entity,
        context: feedback.surface,
      ),
    );
  }
  for (final feedback in await loadEnrichShown(storage)) {
    decisions.add(
      Decision(
        at: feedback.at,
        device: '',
        item: feedback.note,
        source: 'enrich',
        action: 'seen',
        target: feedback.entity,
        context: feedback.surface,
      ),
    );
  }
  return decisions;
}
