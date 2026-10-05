import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/retrieval/native_embedding.dart';

void main() {
  test('native passage embedder requires both model assets', () {
    expect(
      () => nativeEmbedder(modelPath: '', tokenizerPath: 'tokenizer'),
      throwsArgumentError,
    );
    expect(
      () => nativeEmbedder(modelPath: 'model', tokenizerPath: ''),
      throwsArgumentError,
    );
  });

  test('native query embedder shares asset and kind validation', () {
    expect(
      () => nativeEmbedder(
        kind: 'query',
        modelPath: '',
        tokenizerPath: 'tokenizer',
      ),
      throwsArgumentError,
    );
    expect(
      () => nativeEmbedder(
        modelPath: 'model',
        tokenizerPath: 'tokenizer',
        kind: 'other',
      ),
      throwsArgumentError,
    );
  });
}
