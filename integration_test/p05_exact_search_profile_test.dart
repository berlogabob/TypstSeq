import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:tylog/retrieval/cosine_search.dart';
import 'package:tylog/retrieval/vector_index.dart';
import 'package:typst_flutter/src/rust/api/embedding.dart';
import 'package:typst_flutter/src/rust/frb_generated.dart';

/// With P05_HANDSHAKE the host pushes model_O4.onnx + tokenizer.json (see
/// p05_embedding_profile_test) and every run embeds a real query first, so
/// the timing is query embedding + top 20 with model and vectors resident.
const _handshake = bool.fromEnvironment('P05_HANDSHAKE');

/// P05_COMPACT: the app's search shape — an int8 scan copy ranks candidates and
/// the top 200 are reranked with exact Float32 vectors. No Float32 copy of
/// the corpus is kept; each vector is regenerated from its row seed.
const _compact = bool.fromEnvironment('P05_COMPACT');

Float32List _rowVector(int row, int dimension) {
  final random = Random(row);
  return Float32List.fromList([
    for (var j = 0; j < dimension; j++) random.nextDouble() * 2 - 1,
  ]);
}

Future<({String model, String tokenizer})> _awaitPushedModel() async {
  final dir = Directory('${(await getExternalStorageDirectory())!.path}/p05');
  if (dir.existsSync()) dir.deleteSync(recursive: true);
  await dir.create(recursive: true);
  // ignore: avoid_print
  print('P05_READY ${dir.path}');
  for (var i = 0; i < 1200; i++) {
    if (File('${dir.path}/.done').existsSync()) break;
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
  return (
    model: '${dir.path}/model_O4.onnx',
    tokenizer: '${dir.path}/tokenizer.json',
  );
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('P05 250k exact search profile gate', (_) async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    const count = 250000;
    const dimension = 384;
    final random = Random(0);
    final vectors = Float32List(_compact ? 0 : count * dimension);
    for (var i = 0; i < vectors.length; i++) {
      vectors[i] = random.nextDouble() * 2 - 1;
    }
    CompactVectorIndex? index;
    if (_compact) {
      final builder = CompactVectorIndexBuilder(count, dimension);
      for (var row = 0; row < count; row++) {
        builder.add(row.toString().padLeft(6, '0'), _rowVector(row, dimension));
      }
      index = builder.build();
    }
    final ids = List<String>.generate(
      count,
      (i) => i.toString().padLeft(6, '0'),
      growable: false,
    );
    final synthetic = List<double>.generate(
      dimension,
      (_) => random.nextDouble() * 2 - 1,
    );
    final model = _handshake ? await _awaitPushedModel() : null;
    if (model != null) {
      try {
        await RustLib.init();
      } on StateError catch (error) {
        if (!error.message.contains('twice')) rethrow;
      }
    }
    Future<List<double>> queryFor(int run) async {
      if (model == null) return synthetic;
      final result = await embed(
        modelPath: model.model,
        tokenizerPath: model.tokenizer,
        kind: 'query',
        text: 'research question $run',
      );
      return result.vector.map((v) => v.toDouble()).toList();
    }

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
      final query = await queryFor(run);
      final hits = index == null
          ? topCosineHits(query: query, candidates: candidates(), limit: 20)
          : topCosineHits(
              query: query,
              candidates: [
                for (final hit in index.top(query, 200))
                  (
                    id: hit.id,
                    embedding: _rowVector(
                      int.parse(hit.id),
                      dimension,
                    ).buffer.asUint8List(),
                  ),
              ],
              limit: 20,
            );
      timer.stop();
      timesMs.add(timer.elapsedMicroseconds / 1000);
      final actualIds = hits.map((hit) => hit.id).join(',');
      // Real queries differ per run, so only synthetic runs must repeat.
      if (hits.length != 20 ||
          (model == null && expectedIds != null && actualIds != expectedIds)) {
        fail('P05 retrieval result was incomplete or non-deterministic');
      }
      expectedIds ??= actualIds;
    }
    final warm = timesMs.skip(1).toList()..sort();
    // Diagnostic only: keep the process alive for a host-side meminfo dump.
    const hold = int.fromEnvironment('P05_HOLD_SECONDS');
    if (hold > 0) {
      // ignore: avoid_print
      print('P05_HOLDING');
      await Future<void>.delayed(const Duration(seconds: hold));
    }
    // Aggregate-only output; synthetic vectors and IDs are not printed.
    // ignore: avoid_print
    print(
      'P05_ANDROID_EXACT_SEARCH ${jsonEncode({'vectors': count, 'dimension': dimension, 'cold_ms': timesMs.first, 'warm_p50_ms': warm[14], 'warm_p95_ms': warm[28], 'runs': timesMs.length, 'deterministic': model == null, 'query_embedding': model != null, 'compact_index': _compact})}',
    );
    expect(timesMs.first, lessThanOrEqualTo(6000));
    expect(warm[28], lessThanOrEqualTo(3000));
  });
}
