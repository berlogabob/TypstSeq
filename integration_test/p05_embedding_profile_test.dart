import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:typst_flutter/src/rust/api/embedding.dart';
import 'package:typst_flutter/src/rust/frb_generated.dart';

const _modelPath = String.fromEnvironment('P05_MODEL_PATH');
const _tokenizerPath = String.fromEnvironment('P05_TOKENIZER_PATH');
const _goldenPath = String.fromEnvironment('P05_GOLDEN_PATH');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('P05 offline embedding native profile smoke', (_) async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    if (_modelPath.isEmpty || _tokenizerPath.isEmpty || _goldenPath.isEmpty) {
      fail('P05 model, tokenizer, and golden vector paths are required');
    }

    try {
      await RustLib.init();
    } on StateError catch (error) {
      if (!error.message.contains('twice')) rethrow;
    }

    final result = await embed(
      modelPath: _modelPath,
      tokenizerPath: _tokenizerPath,
      kind: 'query',
      text: 'offline smoke text',
    );
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
  });
}
