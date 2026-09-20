import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/retrieval/cosine_search.dart';

List<int> vector(List<double> values) =>
    Float32List.fromList(values).buffer.asUint8List();

void main() {
  test('cosine search ranks vectors and breaks ties by id', () {
    final hits = topCosineHits(
      query: const [1, 0],
      candidates: [
        (id: 'b', embedding: vector([1, 0])),
        (id: 'a', embedding: vector([1, 0])),
        (id: 'c', embedding: vector([0, 1])),
      ],
    );
    expect(hits.map((hit) => hit.id), ['a', 'b', 'c']);
    expect(hits.first.score, closeTo(1, 0.0001));
  });

  test('bounded results match full ranking on a randomized corpus', () {
    final random = math.Random(42);
    final candidates = [
      for (var i = 0; i < 30; i++)
        (
          id: 'id${i.toString().padLeft(2, '0')}',
          embedding: vector([
            random.nextDouble() * 2 - 1,
            random.nextDouble() * 2 - 1,
          ]),
        ),
    ];
    final hits = topCosineHits(
      query: const [3, 1],
      candidates: candidates,
      limit: 7,
    );
    final expected =
        [
          for (final candidate in candidates)
            VectorHit(
              id: candidate.id,
              score: _cosine(
                const [3, 1],
                Uint8List.fromList(candidate.embedding).buffer.asFloat32List(),
              ),
            ),
        ]..sort((a, b) {
          final score = b.score.compareTo(a.score);
          return score == 0 ? a.id.compareTo(b.id) : score;
        });
    expect(hits.map((hit) => hit.id), expected.take(7).map((hit) => hit.id));
  });

  test('skips invalid vectors and handles large finite norms', () {
    final hits = topCosineHits(
      query: const [1e30, 0],
      candidates: [
        (id: 'nan', embedding: vector([double.nan, 1])),
        (id: 'zero', embedding: vector([0, 0])),
        (id: 'good', embedding: vector([3.4e38, 0])),
      ],
    );
    expect(hits.map((hit) => hit.id), ['good']);
    expect(hits.single.score, closeTo(1, 0.0001));
  });
}

double _cosine(List<double> a, List<double> b) {
  final dot = a[0] * b[0] + a[1] * b[1];
  final aNorm = math.sqrt(a[0] * a[0] + a[1] * a[1]);
  final bNorm = math.sqrt(b[0] * b[0] + b[1] * b[1]);
  return dot / (aNorm * bNorm);
}
