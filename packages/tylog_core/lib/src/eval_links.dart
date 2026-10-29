/// Gold-set evaluation of the Links resolver without writing to the vault.
library;

import 'dart:convert';
import 'dart:math';

import 'enrich.dart';
import 'models.dart';
import 'storage.dart';

Future<EnrichMentions> _readMentions(VaultStorage storage, String path) async {
  final mentions = EnrichMentions.tryParse(
    jsonDecode(await storage.readText(path)),
  );
  if (mentions == null) throw FormatException('Invalid mentions file: $path');
  return mentions;
}

EnrichDecision? _resolve(
  EnrichMentions extracted,
  EnrichMention mention,
  VaultIndex index,
  EnrichMemory memory,
) {
  final note = index.notesByPath[extracted.note];
  if (note == null) {
    throw StateError('Note absent from index: ${extracted.note}');
  }
  return resolveMentions(
    EnrichMentions(
      note: extracted.note,
      contentSha: extracted.contentSha,
      mentions: [mention],
    ),
    note,
    memory,
  ).firstOrNull;
}

/// Sorted input plus a fixed seed makes repeated labelling samples reproducible.
/// Gold identifies mentions by note+surface, so repeated occurrences use the first.
Future<List<Map<String, Object?>>> sampleLinks(
  VaultStorage storage,
  VaultIndex index,
  int count,
) async {
  if (count <= 0) throw ArgumentError.value(count, 'count', 'must be positive');
  final files =
      (await storage.list(path: enrichMentionsDir, recursive: true))
          .where((file) => !file.isDirectory && file.path.endsWith('.json'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  final memory = EnrichMemory.build(index, await loadEnrichFeedback(storage));
  final rows = <Map<String, Object?>>[];
  final seen = <(String, String)>{};
  for (final file in files) {
    final extracted = await _readMentions(storage, file.path);
    for (final mention in extracted.mentions) {
      if (!seen.add((extracted.note, mention.surface))) continue;
      final decision = _resolve(extracted, mention, index, memory);
      rows.add({
        'note': extracted.note,
        'surface': mention.surface,
        'type': mention.type,
        'candidates': [
          for (final c in decision?.candidates ?? <EnrichCandidate>[])
            c.note.id,
        ],
        'entity': null,
      });
    }
  }
  if (count > rows.length) {
    throw StateError(
      'Requested $count mentions; only ${rows.length} available',
    );
  }
  rows.shuffle(Random(42));
  return rows.take(count).toList();
}

/// Each gold row is evaluated in isolation; its own feedback never trains it.
Future<String> evaluateLinks(
  VaultStorage storage,
  VaultIndex index,
  String goldJsonl,
) async {
  final feedback = await loadEnrichFeedback(storage);
  final baseline = EnrichMemory.build(index);
  final counts = [List<int>.filled(4, 0), List<int>.filled(4, 0)];
  var n = 0;
  for (final line in const LineSplitter().convert(goldJsonl)) {
    if (line.trim().isEmpty) continue;
    final row = jsonDecode(line);
    if (row is! Map ||
        row['note'] is! String ||
        (row['note'] as String).isEmpty ||
        row['surface'] is! String ||
        (row['surface'] as String).isEmpty ||
        row['entity'] is! String ||
        (row['entity'] as String).isEmpty) {
      throw FormatException(
        'Gold line ${n + 1} requires note, surface and a filled entity',
      );
    }
    final note = row['note'] as String;
    final surface = row['surface'] as String;
    final entity = row['entity'] as String;
    if (entity != 'none' && !baseline.entities.containsKey(entity)) {
      throw FormatException('Unknown gold entity: $entity');
    }
    final extracted = await _readMentions(storage, enrichMentionsPath(note));
    if (extracted.note != note) {
      throw FormatException('Mentions note mismatch: $note');
    }
    final mention = extracted.mentions
        .where((m) => m.surface == surface)
        .firstOrNull;
    if (mention == null) {
      throw FormatException('Mention absent: $note / $surface');
    }
    final learned = EnrichMemory.build(
      index,
      feedback.where(
        (event) =>
            !(event.note == note &&
                enrichKey(event.surface) == enrichKey(surface)),
      ),
    );
    for (final (i, memory) in [baseline, learned].indexed) {
      final decision = _resolve(extracted, mention, index, memory);
      final bucket = switch (decision?.status) {
        EnrichStatus.linked => decision!.target?.id == entity ? 0 : 1,
        EnrichStatus.review => 2,
        // Non-page types can be suppressed by the resolver; still count them.
        EnrichStatus.propose || null => 3,
      };
      counts[i][bucket]++;
    }
    n++;
  }
  String ratio(int numerator, int denominator) =>
      denominator == 0 ? 'n/a' : (numerator / denominator).toStringAsFixed(4);
  return [
    '# Links gold evaluation',
    '',
    '| Memory | n | linked-correct | linked-wrong | review (abstained) | propose | precision | coverage | accuracy |',
    '| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |',
    for (final (i, c) in counts.indexed)
      '| ${i == 0 ? 'Empty ledger' : 'Held-out ledger'} | $n | ${c[0]} | ${c[1]} | ${c[2]} | ${c[3]} | ${ratio(c[0], c[0] + c[1])} | ${ratio(c[0] + c[1], n)} | ${ratio(c[0], n)} |',
    '',
    'Precision = correct / (correct + wrong); coverage = (correct + wrong) / n; accuracy = linked-correct / n.',
    'Gold "none" is never a correct link; review and propose count as abstentions for accuracy.',
    '',
  ].join('\n');
}
