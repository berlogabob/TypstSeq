// Why did the resolver link, or not link, each gold mention? One line per cause.
//   dart run tool/link_misses.dart <vault> <gold.jsonl>
import 'dart:convert';
import 'dart:io';
import 'package:tylog_core/tylog_core.dart';

Future<void> main(List<String> args) async {
  final storage = LocalVaultStorage(Directory(args[0]));
  final index = (await loadVaultIndex(storage))!;
  final memory = EnrichMemory.build(index, await loadEnrichFeedback(storage));
  final byId = {for (final n in index.notes) n.id: n};
  final counts = <String, int>{};
  final examples = <String, List<String>>{};
  for (final line in File(args[1]).readAsLinesSync()) {
    if (line.trim().isEmpty) continue;
    final row = jsonDecode(line) as Map;
    final note = index.notesByPath[row['note']];
    final extracted = EnrichMentions.tryParse(
      jsonDecode(
        await storage.readText(enrichMentionsPath(row['note'] as String)),
      ),
    )!;
    final mention = extracted.mentions.firstWhere(
      (m) => m.surface == row['surface'],
    );
    final decision = resolveMentions(
      EnrichMentions(
        note: extracted.note,
        contentSha: extracted.contentSha,
        mentions: [mention],
      ),
      note!,
      memory,
    ).firstOrNull;
    final gold = row['entity'] as String;
    final status = decision?.status.name ?? 'dropped';
    final cands = [
      for (final c in decision?.candidates ?? <EnrichCandidate>[]) c.note,
    ];
    String cause;
    if (gold == 'none') {
      cause = 'gold none -> $status';
    } else if (status == 'linked') {
      cause = decision!.target?.id == gold ? 'linked correct' : 'linked WRONG';
    } else {
      final goldNote = byId[gold];
      final inCands = cands.any((c) => c.id == gold);
      final key = enrichKey(row['surface'] as String);
      final goldExact =
          goldNote != null &&
          [goldNote.title, ...goldNote.aliases].any((n) => enrichKey(n) == key);
      if (!inCands) {
        cause = goldNote != null && !memory.entities.containsKey(gold)
            ? 'miss: gold page is not a link target (kind ${goldNote.kind})'
            : goldExact
            ? 'miss: exact-name page not among candidates'
            : 'miss: gold page not found (other language / form / partial name)';
      } else {
        final sameName = cands
            .where(
              (c) =>
                  c.id != gold &&
                  [c.title, ...c.aliases].any((n) => enrichKey(n) == key),
            )
            .length;
        final others = cands.length - 1;
        cause = others == 0
            ? 'review: gold is the only candidate, not confident'
            : sameName > 0
            ? 'review: another page has the same name (duplicate)'
            : goldExact
            ? 'review: exact-name page vs pages that only contain the word'
            : 'review: several partial matches';
      }
    }
    counts[cause] = (counts[cause] ?? 0) + 1;
    (examples[cause] ??= []).add('${row['surface']}');
  }
  final keys = counts.keys.toList()
    ..sort((a, b) => counts[b]!.compareTo(counts[a]!));
  for (final k in keys) {
    print(
      '${counts[k].toString().padLeft(4)}  $k   e.g. ${examples[k]!.take(5).join(' | ')}',
    );
  }
}
