import 'package:typst_flutter/typst_flutter.dart' show embed;

import 'embedding_jobs.dart';

ChunkEmbedder nativePassageEmbedder({
  required String modelPath,
  required String tokenizerPath,
}) {
  if (modelPath.isEmpty || tokenizerPath.isEmpty) {
    throw ArgumentError('model and tokenizer paths are required');
  }
  return (text) async {
    final result = await embed(
      modelPath: modelPath,
      tokenizerPath: tokenizerPath,
      kind: 'passage',
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
