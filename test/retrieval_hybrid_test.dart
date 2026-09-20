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
}
