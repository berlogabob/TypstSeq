import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/retrieval/cosine_search.dart';
import 'package:tylog/retrieval/vector_index.dart';

void main() {
  test('int8 scores stay within 1% of exact cosine', () {
    final random = Random(3);
    final a = [for (var j = 0; j < 384; j++) random.nextDouble() * 2 - 1];
    final b = [for (var j = 0; j < 384; j++) random.nextDouble() * 2 - 1];
    final index = (CompactVectorIndexBuilder(1, 384)..add('b', b)).build();
    final exact = topCosineHits(
      query: a,
      candidates: [
        (id: 'b', embedding: Float32List.fromList(b).buffer.asUint8List()),
      ],
    ).single.score;
    expect(index.top(a, 1).single.score, closeTo(exact, 0.01));
  });

  test('int8 candidates reranked in fp32 give the exact top 20', () {
    const count = 5000;
    const dimension = 384;
    final random = Random(7);
    final vectors = [
      for (var i = 0; i < count; i++)
        Float32List.fromList([
          for (var j = 0; j < dimension; j++) random.nextDouble() * 2 - 1,
        ]),
    ];
    final ids = [for (var i = 0; i < count; i++) i.toString().padLeft(5, '0')];
    final builder = CompactVectorIndexBuilder(count, dimension);
    for (var i = 0; i < count; i++) {
      builder.add(ids[i], vectors[i]);
    }
    final index = builder.build();
    for (var trial = 0; trial < 20; trial++) {
      final query = [
        for (var j = 0; j < dimension; j++) random.nextDouble() * 2 - 1,
      ];
      Iterable<({String id, List<int> embedding})> rows(Iterable<int> which) =>
          which.map(
            (i) => (id: ids[i], embedding: vectors[i].buffer.asUint8List()),
          );
      final exact = topCosineHits(
        query: query,
        candidates: rows(Iterable.generate(count)),
        limit: 20,
      );
      final approx = index.top(query, 200).map((hit) => int.parse(hit.id));
      final reranked = topCosineHits(
        query: query,
        candidates: rows(approx),
        limit: 20,
      );
      expect(reranked.map((h) => h.id), exact.map((h) => h.id));
      expect(reranked.first.score, exact.first.score);
    }
  });

  test('invalid rows and queries are ignored', () {
    final builder = CompactVectorIndexBuilder(3, 2)
      ..add('zero', [0, 0])
      ..add('nan', [double.nan, 1])
      ..add('ok', [1, 0]);
    final index = builder.build();
    expect(index.length, 1);
    expect(index.top([0, 0], 5), isEmpty);
    expect(index.top([1, 0], 5).single.id, 'ok');
  });
}
