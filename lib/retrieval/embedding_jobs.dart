import '../database/tylog_database.dart';

typedef ChunkEmbedder = Future<List<int>> Function(String text);

class EmbeddingBatchResult {
  const EmbeddingBatchResult({
    required this.claimed,
    required this.completed,
    required this.failed,
  });

  final int claimed;
  final int completed;
  final int failed;
}

/// Processes a bounded page of pending chunks. A failed item stays pending so
/// the next invocation (or a fresh process) can retry it safely.
Future<EmbeddingBatchResult> runEmbeddingBatch({
  required TyLogDatabase database,
  required String model,
  required ChunkEmbedder embed,
  int limit = 32,
}) async {
  if (limit < 1 || limit > 1000) {
    throw ArgumentError.value(limit, 'limit', 'must be between 1 and 1000');
  }
  final pending = await database.pendingChunks(limit: limit);
  var completed = 0;
  var failed = 0;
  for (final chunk in pending) {
    try {
      final embedding = await embed(chunk.content);
      if (embedding.isEmpty) {
        throw StateError('embedder returned an empty vector');
      }
      await database.completeChunk(
        chunk.id,
        model: model,
        embedding: embedding,
      );
      completed++;
    } catch (_) {
      failed++;
    }
  }
  return EmbeddingBatchResult(
    claimed: pending.length,
    completed: completed,
    failed: failed,
  );
}
