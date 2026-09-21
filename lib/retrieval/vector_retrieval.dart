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
