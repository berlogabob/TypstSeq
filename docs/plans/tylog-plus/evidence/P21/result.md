# P21 progress — vector retrieval primitive

Status: RUNNING

Added bounded cosine top-K over stored Float32-compatible BLOBs and deterministic reciprocal-rank fusion with the existing FTS5 keyword IDs. Scores are normalized, malformed dimensions are skipped, and equal scores sort by stable IDs. Fusion avoids comparing incompatible keyword/vector score scales and keeps the query interface independent of a future sqlite-vec backend.
Retrieved chunk IDs now resolve to their source, immutable source-version ID, and stable character offsets for cited navigation.

Evidence:

- `flutter test test/retrieval_cosine_test.dart` — ranking and tie-break checks pass.
- `flutter analyze lib/retrieval/cosine_search.dart test/retrieval_cosine_test.dart` — clean.
- `flutter test test/retrieval_hybrid_test.dart` — agreement ranking and empty-limit behavior pass.
- `flutter test test/database/chunk_persistence_test.dart` — retrieved chunks resolve to stable source ranges.

Remaining work: connect this target to the reader UI and measure corpus latency/memory gates.
