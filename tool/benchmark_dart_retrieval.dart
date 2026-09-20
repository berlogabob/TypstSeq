import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:tylog/retrieval/cosine_search.dart';

// Synthetic primitive benchmark, excluding embeddings, SQLite, and UI latency.
void main(List<String> args) {
  final count = args.isEmpty ? 10000 : int.parse(args.single);
  if (count < 20 || count > 250000) {
    throw ArgumentError('count must be 20..250000');
  }
  const dimension = 384;
  final random = Random(0);
  final vectors = Float32List(count * dimension);
  for (var i = 0; i < vectors.length; i++) {
    vectors[i] = random.nextDouble() * 2 - 1;
  }
  final query = List<double>.generate(
    dimension,
    (_) => random.nextDouble() * 2 - 1,
  );
  Iterable<({String id, List<int> embedding})> candidates() sync* {
    for (var i = 0; i < count; i++) {
      yield (
        id: i.toString().padLeft(6, '0'),
        embedding: Uint8List.view(
          vectors.buffer,
          i * dimension * 4,
          dimension * 4,
        ),
      );
    }
  }

  final timings = <double>[];
  List<String>? expected;
  for (var run = 0; run < 31; run++) {
    final timer = Stopwatch()..start();
    final hits = topCosineHits(
      query: query,
      candidates: candidates(),
      limit: 20,
    );
    timer.stop();
    timings.add(timer.elapsedMicroseconds / 1000);
    final ids = hits.map((hit) => hit.id).toList();
    if (ids.length != 20 ||
        (expected != null && ids.join(',') != expected.join(','))) {
      throw StateError('Non-deterministic retrieval');
    }
    expected = ids;
  }
  final warm = timings.skip(1).toList()..sort();
  stdout.writeln(
    jsonEncode({
      'vectors': count,
      'dimension': dimension,
      'warm_samples': warm.length,
      'cold_ms': timings.first,
      'warm_p50_ms': warm[14],
      'warm_p95_ms': warm[28],
      'max_rss_bytes': ProcessInfo.maxRss,
      'runtime': Platform.version,
      'scope': 'synthetic Dart cosine only; not end-to-end acceptance',
    }),
  );
}
