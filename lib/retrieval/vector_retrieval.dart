import 'dart:typed_data';

import '../database/tylog_database.dart';
import 'cosine_search.dart';
import 'embedding_jobs.dart';
import 'hybrid_search.dart';

List<double> _decodeQueryEmbedding(List<int> bytes) {
  if (bytes.isEmpty || bytes.length % 4 != 0) {
    throw StateError('query embedder returned invalid Float32 bytes');
  }
  final values = Uint8List.fromList(bytes).buffer.asFloat32List();
  if (values.isEmpty || values.any((value) => !value.isFinite)) {
    throw StateError('query embedder returned invalid Float32 values');
  }
  return values.toList(growable: false);
}

Future<List<VectorHit>> searchStoredChunks({
  required TyLogDatabase database,
  required String model,
  required List<double> query,
  int limit = 10,
  int candidateLimit = 10000,
}) async {
  final candidates = await database.embeddedChunkCandidates(
    model: model,
    limit: candidateLimit,
  );
  return topCosineHits(query: query, candidates: candidates, limit: limit);
}

Future<List<HybridHit>> searchStoredChunksHybrid({
  required TyLogDatabase database,
  required String model,
  required List<double> query,
  required Iterable<String> keywordIds,
  int limit = 10,
  int candidateLimit = 10000,
}) async {
  final vectors = await searchStoredChunks(
    database: database,
    model: model,
    query: query,
    limit: limit,
    candidateLimit: candidateLimit,
  );
  return fuseSearchHits(
    keywordIds: keywordIds,
    vectorHits: vectors,
    limit: limit,
  );
}

/// Runs the production-shaped query path: embed the query, search vectors, and
/// fuse them with the caller's bounded FTS IDs.
Future<List<HybridHit>> searchStoredChunksHybridWithQueryEmbedder({
  required TyLogDatabase database,
  required String model,
  required ChunkEmbedder queryEmbedder,
  required String query,
  required Iterable<String> keywordIds,
  int limit = 10,
  int candidateLimit = 10000,
}) async {
  final queryVector = _decodeQueryEmbedding(await queryEmbedder(query));
  return searchStoredChunksHybrid(
    database: database,
    model: model,
    query: queryVector,
    keywordIds: keywordIds,
    limit: limit,
    candidateLimit: candidateLimit,
  );
}

/// Fuses stored vectors with keyword IDs and resolves stable source offsets in
/// the same ranked order. Missing chunks are omitted rather than re-ranked.
Future<
  List<
    ({
      HybridHit hit,
      String sourceId,
      String sourceVersionId,
      int startOffset,
      int endOffset,
    })
  >
>
searchStoredChunksHybridWithNavigation({
  required TyLogDatabase database,
  required String model,
  required List<double> query,
  required Iterable<String> keywordIds,
  int limit = 10,
  int candidateLimit = 10000,
}) async {
  final hits = await searchStoredChunksHybrid(
    database: database,
    model: model,
    query: query,
    keywordIds: keywordIds,
    limit: limit,
    candidateLimit: candidateLimit,
  );
  final navigation = {
    for (final row in await database.navigationForChunks(
      hits.map((hit) => hit.id),
    ))
      row.chunkId: row,
  };
  return [
    for (final hit in hits)
      if (navigation[hit.id] case final row?)
        (
          hit: hit,
          sourceId: row.sourceId,
          sourceVersionId: row.sourceVersionId,
          startOffset: row.startOffset,
          endOffset: row.endOffset,
        ),
  ];
}

Future<List<ChunkCitation>> resolveChunkCitations({
  required TyLogDatabase database,
  required Iterable<VectorHit> hits,
}) async {
  final rows = await database.pdfCitationsForChunks(hits.map((hit) => hit.id));
  return [
    for (final row in rows)
      ChunkCitation(
        chunkId: row.chunkId,
        sourceId: row.sourceId,
        sourceKind: row.sourceKind,
        sourceLocator: row.sourceLocator,
        sourceTitle: row.sourceTitle,
        sourceVersionId: row.sourceVersionId,
        startOffset: row.startOffset,
        endOffset: row.endOffset,
        content: row.content,
      ),
  ];
}
