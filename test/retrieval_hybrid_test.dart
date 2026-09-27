import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/retrieval/cosine_search.dart';
import 'package:tylog/retrieval/hybrid_search.dart';
import 'package:tylog/search_index.dart';

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

  test('typed merger preserves metadata for fused IDs', () {
    const keyword = [
      PkmsSearchResult(
        id: 'a',
        path: 'a.typ',
        title: 'A',
        kind: 'note',
        tags: [],
        score: 1,
      ),
      PkmsSearchResult(
        id: 'b',
        path: 'b.typ',
        title: 'B',
        kind: 'note',
        tags: [],
        score: 1,
      ),
    ];
    final merged = mergeHybridSearchResults(
      keywordResults: keyword,
      vectorHits: const [
        VectorHit(id: 'b', score: 0.9),
        VectorHit(id: 'missing', score: 0.8),
      ],
    );

    expect(merged.map((result) => result.id), ['b', 'a']);
    expect(merged.first.path, 'b.typ');
  });

  test('typed merger resolves vector-only IDs when requested', () {
    final merged = mergeHybridSearchResults(
      keywordResults: const [],
      vectorHits: const [VectorHit(id: 'notes/a.typ', score: 1)],
      resolveMissing: (id) => PkmsSearchResult(
        id: id,
        path: id,
        title: 'A',
        kind: 'note',
        tags: const [],
        score: 0,
      ),
      limit: 1,
    );
    expect(merged.single.path, 'notes/a.typ');
  });
}
