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
}
