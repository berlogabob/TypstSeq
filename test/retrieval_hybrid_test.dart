import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/retrieval/cosine_search.dart';
import 'package:tylog/retrieval/hybrid_search.dart';

void main() {
  test('reciprocal-rank fusion rewards agreement and is deterministic', () {
    final hits = fuseSearchHits(
      keywordIds: const ['b', 'a'],
      vectorHits: const [
        VectorHit(id: 'a', score: 0.9),
        VectorHit(id: 'c', score: 0.8),
      ],
    );
    expect(hits.map((hit) => hit.id), ['a', 'b', 'c']);
    expect(
      fuseSearchHits(keywordIds: const [], vectorHits: const [], limit: 0),
      isEmpty,
    );
  });

  test('duplicate IDs contribute once per ranking', () {
    final hits = fuseSearchHits(
      keywordIds: const ['a', 'a', 'b'],
      vectorHits: const [
        VectorHit(id: 'a', score: 1),
        VectorHit(id: 'a', score: 0.9),
        VectorHit(id: 'b', score: 0.8),
      ],
    );
    expect(hits.map((hit) => hit.id), ['a', 'b']);
    expect(hits.first.score, closeTo(2 / 61, 0.000001));
  });
}
