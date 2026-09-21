import 'package:typst_flutter/typst_flutter.dart' show embed;

import 'embedding_jobs.dart';

ChunkEmbedder nativeEmbedder({
  required String modelPath,
  required String tokenizerPath,
  String kind = 'passage',
}) {
  if (modelPath.isEmpty || tokenizerPath.isEmpty) {
    throw ArgumentError('model and tokenizer paths are required');
  }
  if (kind != 'query' && kind != 'passage') {
    throw ArgumentError.value(kind, 'kind', 'must be query or passage');
  }
  return (text) async {
    final result = await embed(
      modelPath: modelPath,
      tokenizerPath: tokenizerPath,
      kind: kind,
      text: text,
    );
    if (!result.finite ||
        result.dimension != 384 ||
        result.vector.length != 384) {
      throw StateError('native embedder returned an invalid vector');
    }
    return result.vector.buffer.asUint8List().toList(growable: false);
  };
}

ChunkEmbedder nativePassageEmbedder({
  required String modelPath,
  required String tokenizerPath,
}) => nativeEmbedder(modelPath: modelPath, tokenizerPath: tokenizerPath);

ChunkEmbedder nativeQueryEmbedder({
  required String modelPath,
  required String tokenizerPath,
}) => nativeEmbedder(
  modelPath: modelPath,
  tokenizerPath: tokenizerPath,
  kind: 'query',
);
