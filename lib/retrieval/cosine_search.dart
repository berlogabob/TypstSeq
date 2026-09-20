import 'dart:math' as math;
import 'dart:typed_data';

class VectorHit {
  const VectorHit({required this.id, required this.score});

  final String id;
  final double score;
}

List<VectorHit> topCosineHits({
  required List<double> query,
  required Iterable<({String id, List<int> embedding})> candidates,
  int limit = 10,
}) {
  if (query.isEmpty || limit <= 0) return const [];
  final queryNorm = math.sqrt(
    query.fold(0.0, (sum, value) => sum + value * value),
  );
  if (queryNorm == 0 || !queryNorm.isFinite) return const [];
  final hits = <VectorHit>[];
  for (final candidate in candidates) {
    final bytes = Uint8List.fromList(candidate.embedding);
    if (bytes.length % 4 != 0) continue;
    final vector = bytes.buffer.asFloat32List();
    if (vector.length != query.length) continue;
    var dot = 0.0;
    var norm = 0.0;
    for (var i = 0; i < vector.length; i++) {
      final value = vector[i];
      dot += query[i] * value;
      norm += value * value;
    }
    if (norm == 0 || !norm.isFinite) continue;
    hits.add(
      VectorHit(id: candidate.id, score: dot / (queryNorm * math.sqrt(norm))),
    );
  }
  hits.sort((a, b) {
    final score = b.score.compareTo(a.score);
    return score == 0 ? a.id.compareTo(b.id) : score;
  });
  return hits.take(limit).toList(growable: false);
}
