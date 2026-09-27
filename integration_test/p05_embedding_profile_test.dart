import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:typst_flutter/src/rust/api/embedding.dart';
import 'package:typst_flutter/src/rust/frb_generated.dart';

const _handshake = bool.fromEnvironment('P05_HANDSHAKE');
var _modelPath = const String.fromEnvironment('P05_MODEL_PATH');
var _tokenizerPath = const String.fromEnvironment('P05_TOKENIZER_PATH');
var _goldenPath = const String.fromEnvironment('P05_GOLDEN_PATH');

/// Android: the app creates its own external dir, prints P05_READY, and waits
/// for the host to push model_O4.onnx, tokenizer.json, smoke-golden.json and a
/// .done marker (adb cannot create app-owned dirs).
Future<void> _awaitPushedModel() async {
  final dir = Directory('${(await getExternalStorageDirectory())!.path}/p05');
  // Start empty so files left by an earlier run can never be measured.
  if (dir.existsSync()) dir.deleteSync(recursive: true);
  await dir.create(recursive: true);
  // ignore: avoid_print
  print('P05_READY ${dir.path}');
  for (var i = 0; i < 1200; i++) {
    if (File('${dir.path}/.done').existsSync()) break;
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
  // A pushed ORT-format model (zero-copy load) wins over the .onnx original.
  _modelPath = File('${dir.path}/model.ort').existsSync()
      ? '${dir.path}/model.ort'
      : '${dir.path}/model_O4.onnx';
  _tokenizerPath = '${dir.path}/tokenizer.json';
  _goldenPath = '${dir.path}/smoke-golden.json';
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'P05 offline embedding native profile smoke',
    (_) async {
      // Native ORT is built for arm64 Android and Apple-silicon macOS only.
      if (defaultTargetPlatform != TargetPlatform.android &&
          defaultTargetPlatform != TargetPlatform.macOS) {
        return;
      }

      if (_handshake) await _awaitPushedModel();
      try {
        await RustLib.init();
      } on StateError catch (error) {
        if (!error.message.contains('twice')) rethrow;
      }

      final first = Stopwatch()..start();
      final result = await embed(
        modelPath: _modelPath,
        tokenizerPath: _tokenizerPath,
        kind: 'query',
        text: 'offline smoke text',
      );
      final firstUs = first.elapsedMicroseconds;
      final expected =
          (jsonDecode(await File(_goldenPath).readAsString()) as List)
              .cast<num>()
              .map((value) => value.toDouble())
              .toList();
      expect(result.dimension, 384);
      expect(result.vector.length, 384);
      expect(expected.length, result.vector.length);
      expect(result.finite, isTrue);
      expect(result.norm, closeTo(1.0, 0.0001));
      var dot = 0.0;
      var maxAbsDifference = 0.0;
      for (var i = 0; i < expected.length; i++) {
        final actual = result.vector[i].toDouble();
        dot += actual * expected[i];
        maxAbsDifference = math.max(
          maxAbsDifference,
          (actual - expected[i]).abs(),
        );
      }
      final cosine = dot / result.norm;
      // Aggregate-only parity evidence; inputs and vectors are synthetic.
      // ignore: avoid_print
      print(
        'P05_VECTOR_PARITY cosine=${cosine.toStringAsFixed(6)} '
        'max_abs=${maxAbsDifference.toStringAsFixed(6)}',
      );
      expect(cosine, greaterThanOrEqualTo(0.999));
      expect(maxAbsDifference, lessThanOrEqualTo(0.02));

      // Query-embedding latency: the call above loaded the model (first query);
      // these 20 reuse the cached session (warm). Synthetic text, timings only.
      final warm = <int>[];
      for (var i = 0; i < 20; i++) {
        final watch = Stopwatch()..start();
        await embed(
          modelPath: _modelPath,
          tokenizerPath: _tokenizerPath,
          kind: 'query',
          text: 'offline smoke text $i',
        );
        warm.add(watch.elapsedMicroseconds);
      }
      warm.sort();
      // ignore: avoid_print
      print(
        'P05_QUERY_EMBED_US first=$firstUs warm_p50=${warm[9]} '
        'warm_p95=${warm[18]} warm_max=${warm.last}',
      );
    },
    skip:
        !_handshake &&
        (_modelPath.isEmpty || _tokenizerPath.isEmpty || _goldenPath.isEmpty),
  );
}
