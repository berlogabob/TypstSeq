import '../database/tylog_database.dart';
import 'cosine_search.dart';
import 'hybrid_search.dart';

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
