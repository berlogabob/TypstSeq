import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:typst_flutter/src/rust/api/embedding.dart';
import 'package:typst_flutter/src/rust/frb_generated.dart';

const _modelPath = String.fromEnvironment('P05_MODEL_PATH');
const _tokenizerPath = String.fromEnvironment('P05_TOKENIZER_PATH');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('P05 offline embedding native profile smoke', (_) async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    if (_modelPath.isEmpty || _tokenizerPath.isEmpty) {
      fail('P05_MODEL_PATH and P05_TOKENIZER_PATH are required');
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
    expect(result.dimension, 384);
    expect(result.vector.length, 384);
    expect(result.finite, isTrue);
    expect(result.norm, closeTo(1.0, 0.0001));
  });
}
