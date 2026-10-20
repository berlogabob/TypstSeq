import 'cosine_search.dart';
import 'package:tylog_core/search_index.dart';

class HybridHit {
  const HybridHit({required this.id, required this.score});

  final String id;
  final double score;
}

class ChunkCitation {
  const ChunkCitation({
    required this.chunkId,
    required this.sourceId,
    required this.sourceKind,
    required this.sourceLocator,
    required this.sourceVersionId,
    required this.startOffset,
    required this.endOffset,
    required this.content,
    this.sourceTitle,
  });

  final String chunkId;
  final String sourceId;
  final String sourceKind;
  final String sourceLocator;
  final String? sourceTitle;
  final String sourceVersionId;
  final int startOffset;
  final int endOffset;
  final String content;
}

/// Resolves citation locators without treating any punctuation in a path or
/// title as a delimiter.
String? resolveCitationPath({
  required String sourceId,
  required String sourceLocator,
  String? sourceTitle,
  required Map<String, String> pathsById,
  required Map<String, String> locatorsById,
  required Map<String, String> titlesByPath,
}) {
  final candidates = <String?>[
    pathsById[sourceId],
    locatorsById[sourceId],
    sourceLocator,
    if (sourceId.startsWith('note:')) sourceId.substring('note:'.length),
  ];
  for (final path in candidates) {
    if (path != null && titlesByPath.containsKey(path)) return path;
  }
  if (sourceTitle != null) {
    for (final entry in titlesByPath.entries) {
      if (entry.value == sourceTitle) return entry.key;
    }
  }
  return null;
}

/// Merges keyword and vector rankings without comparing incompatible scores.
/// Reciprocal-rank fusion keeps this query path backend-independent. Keyword
/// and vector IDs must use the same entity ID namespace for agreement to work.
List<HybridHit> fuseSearchHits({
  required Iterable<String> keywordIds,
  required Iterable<VectorHit> vectorHits,
  int limit = 10,
  int rankConstant = 60,
}) {
  if (limit <= 0 || rankConstant < 1) return const [];
  final scores = <String, double>{};
  var rank = 0;
  final seenKeywords = <String>{};
  for (final id in keywordIds) {
    if (!seenKeywords.add(id)) continue;
    scores[id] = (scores[id] ?? 0) + 1 / (rankConstant + ++rank);
  }
  rank = 0;
  final seenVectors = <String>{};
  for (final hit in vectorHits) {
    if (!seenVectors.add(hit.id)) continue;
    if (scores.containsKey(hit.id)) {
      scores[hit.id] = scores[hit.id]! + 1 / (rankConstant + ++rank);
    } else {
      scores[hit.id] = 1 / (rankConstant + ++rank);
    }
  }
  final hits = [
    for (final entry in scores.entries)
      HybridHit(id: entry.key, score: entry.value),
  ];
  hits.sort((a, b) {
    final score = b.score.compareTo(a.score);
    return score == 0 ? a.id.compareTo(b.id) : score;
  });
  return hits.take(limit).toList(growable: false);
}

/// Applies the fused ID order to metadata already loaded by the keyword path.
///
/// Vector-only IDs are skipped until the chunk/node identity mapping is
/// finalized; this keeps the UI from rendering incomplete result rows.
List<PkmsSearchResult> mergeHybridSearchResults({
  required Iterable<PkmsSearchResult> keywordResults,
  required Iterable<VectorHit> vectorHits,
  PkmsSearchResult? Function(String id)? resolveMissing,
  int limit = 10,
  String query = '',
}) {
  final results = [for (final result in keywordResults) result];
  final byId = <String, PkmsSearchResult>{
    for (final result in results) result.id: result,
  };
  final fused = fuseSearchHits(
    keywordIds: results.map((result) => result.id),
    vectorHits: vectorHits,
    limit: limit,
  );
  final merged = fused
      .map((hit) => byId[hit.id] ?? resolveMissing?.call(hit.id))
      .whereType<PkmsSearchResult>()
      .toList();
  // A title containing the whole query goes first: rank fusion put "TyLog
  // sync test" third for the query "TyLog sync", under notes that merely
  // scored in both lists. Stable, so fused order holds within each group.
  final needle = query.trim().toLowerCase();
  if (needle.isEmpty) return List.unmodifiable(merged);
  bool titled(PkmsSearchResult r) => r.title.toLowerCase().contains(needle);
  return List.unmodifiable([
    ...merged.where(titled),
    ...merged.where((r) => !titled(r)),
  ]);
}

/// The SQLite projection can lag synced files; keep live-vault keyword hits.
List<PkmsSearchResult> mergeKeywordResults(
  Iterable<PkmsSearchResult> projected,
  Iterable<PkmsSearchResult> live,
) => {
  for (final hit in [...projected, ...live]) hit.path: hit,
}.values.toList()..sort((a, b) => b.score.compareTo(a.score));
