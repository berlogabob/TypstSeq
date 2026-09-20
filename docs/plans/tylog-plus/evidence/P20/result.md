# P20 progress — deterministic chunking

Status: RUNNING

Added deterministic text chunking keyed by source-version ID. Each chunk carries source character offsets, configurable overlap, and a SHA-256 content hash; unchanged source versions therefore produce stable chunk IDs and changed ranges can be re-embedded independently. SQLite schema v8 persists chunks with pending/complete/failed state, model identity, and optional Float32-compatible BLOB embeddings.

Evidence:

- `flutter test test/retrieval_chunking_test.dart` — 2 passed.
- `flutter analyze lib/retrieval/chunking.dart test/retrieval_chunking_test.dart` — clean.
- `flutter test test/database/chunk_persistence_test.dart` — pending-to-complete embedding state and BLOB persistence pass.
- `flutter test test/database/tylog_graph_schema_test.dart test/database/portable_snapshot_test.dart` — v2→v8 migration and snapshot format v8 pass.

Remaining work: connect the pinned offline runtime from P05 and run bounded embedding batches in an isolate.
