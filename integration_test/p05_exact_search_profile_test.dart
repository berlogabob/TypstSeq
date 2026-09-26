import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tylog/retrieval/cosine_search.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('P05 250k exact search profile gate', (_) async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    const count = 250000;
    const dimension = 384;
    final random = Random(0);
    final vectors = Float32List(count * dimension);
    for (var i = 0; i < vectors.length; i++) {
      vectors[i] = random.nextDouble() * 2 - 1;
    }
    final ids = List<String>.generate(
      count,
      (i) => i.toString().padLeft(6, '0'),
      growable: false,
    );
    final query = List<double>.generate(
      dimension,
      (_) => random.nextDouble() * 2 - 1,
    );
    Iterable<({String id, List<int> embedding})> candidates() sync* {
      for (var i = 0; i < count; i++) {
        yield (
          id: ids[i],
          embedding: Uint8List.view(
            vectors.buffer,
            i * dimension * 4,
            dimension * 4,
          ),
        );
      }
    }

    final timesMs = <double>[];
    String? expectedIds;
    for (var run = 0; run < 31; run++) {
      final timer = Stopwatch()..start();
      final hits = topCosineHits(
        query: query,
        candidates: candidates(),
        limit: 20,
      );
      timer.stop();
      timesMs.add(timer.elapsedMicroseconds / 1000);
      final actualIds = hits.map((hit) => hit.id).join(',');
      if (hits.length != 20 ||
          (expectedIds != null && actualIds != expectedIds)) {
        fail('P05 retrieval result was incomplete or non-deterministic');
      }
      expectedIds ??= actualIds;
    }
    final warm = timesMs.skip(1).toList()..sort();
    // Aggregate-only output; synthetic vectors and IDs are not printed.
    // ignore: avoid_print
    print(
      'P05_ANDROID_EXACT_SEARCH ${jsonEncode({'vectors': count, 'dimension': dimension, 'cold_ms': timesMs.first, 'warm_p50_ms': warm[14], 'warm_p95_ms': warm[28], 'runs': timesMs.length, 'deterministic': true})}',
    );
    expect(timesMs.first, lessThanOrEqualTo(6000));
    expect(warm[28], lessThanOrEqualTo(3000));
  });
}
