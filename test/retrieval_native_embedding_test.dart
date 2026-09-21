import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/retrieval/native_embedding.dart';

void main() {
  test('native passage embedder requires both model assets', () {
    expect(
      () => nativePassageEmbedder(modelPath: '', tokenizerPath: 'tokenizer'),
      throwsArgumentError,
    );
    expect(
      () => nativePassageEmbedder(modelPath: 'model', tokenizerPath: ''),
      throwsArgumentError,
    );
  });
}
