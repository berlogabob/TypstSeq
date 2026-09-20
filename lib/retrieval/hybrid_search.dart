import 'cosine_search.dart';

class HybridHit {
  const HybridHit({required this.id, required this.score});

  final String id;
  final double score;
}

/// Merges keyword and vector rankings without comparing incompatible scores.
/// Reciprocal-rank fusion keeps this query path backend-independent.
List<HybridHit> fuseSearchHits({
  required Iterable<String> keywordIds,
  required Iterable<VectorHit> vectorHits,
  int limit = 10,
  int rankConstant = 60,
}) {
  if (limit <= 0 || rankConstant < 1) return const [];
  final scores = <String, double>{};
  var rank = 0;
  for (final id in keywordIds) {
    if (scores.containsKey(id)) continue;
    scores[id] = (scores[id] ?? 0) + 1 / (rankConstant + ++rank);
  }
  rank = 0;
  for (final hit in vectorHits) {
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
