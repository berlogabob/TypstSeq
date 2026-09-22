# P21 progress — vector retrieval primitive

Status: HOST ACCEPTED / DEVICE BLOCKED

Added bounded cosine top-K over stored Float32-compatible BLOBs and deterministic reciprocal-rank fusion with the existing FTS5 keyword IDs. Scores are normalized, malformed dimensions are skipped, and equal scores sort by stable IDs. Fusion avoids comparing incompatible keyword/vector score scales and keeps the query interface independent of a future sqlite-vec backend.
Retrieved chunk IDs now resolve to their source, immutable source-version ID, and stable character offsets for cited navigation.

The production bridge is now present: `embeddedChunkCandidates` loads a bounded, model-filtered set of completed vectors from SQLite, and `searchStoredChunks` feeds those rows into the existing cosine primitive. This keeps the query path bounded and excludes vectors produced by another model. `flutter test test/retrieval_vector_retrieval_test.dart` and targeted analysis pass.

`TyLogDatabase.navigationForChunks` now resolves up to 100 retrieved chunk IDs
in one SQLite query and returns only existing hits in the caller's ranking
order. The chunk persistence suite covers source/version identity and stable
character offsets for a top-K style result list.

The native embedding adapter now exposes both `nativePassageEmbedder` and
`nativeQueryEmbedder` over one validated `nativeEmbedder` seam. The adapter
rejects missing model assets and unsupported kinds before invoking Rust; focused
validation tests pass. Device model execution and quality/latency measurement
remain open.

`searchStoredChunksHybrid` now composes that vector path with reciprocal-rank fusion in one async seam. Focused vector and hybrid tests pass. The seam deliberately accepts keyword IDs from the caller until node/chunk identity mapping is finalized.

`mergeHybridSearchResults` now applies the fused ID order to the existing
`PkmsSearchResult` metadata, preserves durable paths/titles, bounds output, and
skips vector-only IDs until chunk/node identity mapping is finalized. The
focused hybrid suite covers metadata preservation and missing-ID handling.

`searchStoredChunksHybridWithNavigation` now composes the bounded hybrid query
with one batch navigation lookup and returns source/version offsets in fused
rank order. Missing chunk rows are skipped without changing the remaining
order; the vector retrieval suite covers the cited result contract.

Evidence:

- `flutter test test/retrieval_cosine_test.dart` — ranking and tie-break checks pass.
- `flutter analyze lib/retrieval/cosine_search.dart test/retrieval_cosine_test.dart` — clean.
- `flutter test test/retrieval_hybrid_test.dart` — agreement ranking and empty-limit behavior pass.
- `flutter test test/database/chunk_persistence_test.dart` — retrieved chunks resolve to stable source ranges.
- Reference only (not Dart/app acceptance): the P05.3 NumPy exact-cosine benchmark measured 10,000 vectors at 1.266 ms warm p95 / 53.6 MB RSS and 250,000 vectors at 18.115 ms warm p95 / 427.7 MB RSS. Fusion is bounded to the returned keyword/vector candidate lists, so it does not add a corpus-sized pass.

Remaining work: supply the query embedding runtime, call this merger from the
FTS UI, connect cited navigation, and measure corpus latency/memory gates.

Production audit: cosine/fusion/navigation primitives had no app callers at this checkpoint. FTS node IDs and vector chunk IDs must be mapped to the same entity before fusion. The Python benchmark does not measure the Dart implementation, query embedding, or end-to-end retrieval.

Sequential host rerun: cosine, hybrid, vector, chunk-navigation, and native
adapter suites passed 13 tests. Android model execution and UI/native citation
acceptance remain device-gated.

The query seam now has a production-shaped helper,
`searchStoredChunksHybridWithQueryEmbedder`: it invokes the query embedder,
validates Float32 bytes, searches only the selected model's stored vectors, and
fuses the result with bounded FTS IDs. A focused test covers the byte-to-vector
conversion and ranked output. Real model assets and device measurements remain
required before enabling this path by default.

## Host acceptance rerun (2026-09-22)

The combined cosine, hybrid, navigation, vector retrieval, chunk persistence,
and native-adapter suites passed; targeted analysis is clean. Bounded query
seams are accepted on host. Real query-model assets, FTS UI citation wiring,
and Android quality measurements remain open.

## Dart primitive measurements (2026-09-20)

Command: `dart run tool/benchmark_dart_retrieval.dart 10000` and `250000`. macOS ARM64, Dart 3.12.2 JIT; seed 0; 384 Float32 dimensions; top 20; 1 first and 30 warm samples.

| Vectors | First ms | Warm p50 ms | Warm p95 ms | Peak process RSS bytes |
|---:|---:|---:|---:|---:|
| 10,000 | 41.233 | 24.667 | 26.075 | 195,215,360 |
| 250,000 | 708.616 | 655.726 | 665.748 | 562,888,704 |

These numbers measure the actual Dart cosine primitive with a synthetic in-memory Float32 corpus, including per-candidate conversion. They exclude DB retrieval, query embedding, UI, model memory, and Android. Full semantic-search acceptance remains open. Retained hit state is now O(k), with deterministic tie order; duplicate RRF IDs are ignored within each ranking.
