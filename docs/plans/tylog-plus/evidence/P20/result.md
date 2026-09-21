# P20 progress — deterministic chunking

Status: RUNNING

Added deterministic text chunking keyed by source-version ID. Each chunk carries source character offsets, configurable overlap, and a SHA-256 content hash; unchanged source versions therefore produce stable chunk IDs and changed ranges can be re-embedded independently. SQLite schema v8 persists chunks with pending/complete/failed state, model identity, and optional Float32-compatible BLOB embeddings.

Evidence:

- `flutter test test/retrieval_chunking_test.dart` — 2 passed.
- `flutter analyze lib/retrieval/chunking.dart test/retrieval_chunking_test.dart` — clean.
- `flutter test test/database/chunk_persistence_test.dart` — pending-to-complete embedding state and BLOB persistence pass.
- `flutter test test/database/tylog_graph_schema_test.dart test/database/portable_snapshot_test.dart` — v2→v8 migration and snapshot format v8 pass.
- `flutter test test/retrieval_embedding_jobs_test.dart test/database/chunk_persistence_test.dart` — bounded batches persist completed vectors, leave failed work pending, and resume after a fresh runner invocation.
- `flutter analyze lib/retrieval/embedding_jobs.dart test/retrieval_embedding_jobs_test.dart` — clean.

The new `runEmbeddingBatch` seam uses the existing chunk state as its durable queue: it processes at most 1,000 rows, writes each vector before advancing, and leaves failures pending for retry. Remaining work: move the native callback behind an isolate and run Android quality/latency gates.

The pinned ORT bridge is now adapted by `nativePassageEmbedder`, which validates the native 384-dimensional finite result and stores its Float32 bytes through the same batch runner. The package exports this API publicly; host validation covers asset-path checks. Android model smoke and sustained profile measurements remain device-gated.
