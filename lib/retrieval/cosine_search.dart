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
  var queryScale = 0.0;
  for (final value in query) {
    if (!value.isFinite) return const [];
    queryScale = math.max(queryScale, value.abs());
  }
  if (queryScale == 0) return const [];
  var queryNormSquared = 0.0;
  for (final value in query) {
    final scaled = value / queryScale;
    queryNormSquared += scaled * scaled;
  }
  final queryNorm = math.sqrt(queryNormSquared);
  if (!queryNorm.isFinite || queryNorm == 0) return const [];

  // ponytail: O(n*k) bounded list; use a heap only if profiling shows this is hot.
  final hits = <VectorHit>[];
  for (final candidate in candidates) {
    final bytes = Uint8List.fromList(candidate.embedding);
    if (bytes.length % 4 != 0) continue;
    final vector = bytes.buffer.asFloat32List();
    if (vector.length != query.length) continue;
    var vectorScale = 0.0;
    var valid = true;
    for (final value in vector) {
      if (!value.isFinite) {
        valid = false;
        break;
      }
      vectorScale = math.max(vectorScale, value.abs());
    }
    if (!valid || vectorScale == 0) continue;
    var dot = 0.0;
    var vectorNormSquared = 0.0;
    for (var i = 0; i < vector.length; i++) {
      final normalizedVector = vector[i] / vectorScale;
      dot += (query[i] / queryScale) * normalizedVector;
      vectorNormSquared += normalizedVector * normalizedVector;
    }
    final vectorNorm = math.sqrt(vectorNormSquared);
    final score = dot / (queryNorm * vectorNorm);
    if (!score.isFinite) continue;
    final hit = VectorHit(id: candidate.id, score: score);
    var index = 0;
    while (index < hits.length && _compareHits(hits[index], hit) <= 0) {
      index++;
    }
    if (index >= limit && hits.length >= limit) continue;
    hits.insert(index, hit);
    if (hits.length > limit) hits.removeLast();
  }
  return List.unmodifiable(hits);
}

int _compareHits(VectorHit a, VectorHit b) {
  final score = b.score.compareTo(a.score);
  return score == 0 ? a.id.compareTo(b.id) : score;
}
