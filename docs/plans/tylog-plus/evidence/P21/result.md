# P21 progress — vector retrieval primitive

Status: RUNNING

Added bounded cosine top-K over stored Float32-compatible BLOBs and deterministic reciprocal-rank fusion with the existing FTS5 keyword IDs. Scores are normalized, malformed dimensions are skipped, and equal scores sort by stable IDs. Fusion avoids comparing incompatible keyword/vector score scales and keeps the query interface independent of a future sqlite-vec backend.

Evidence:

- `flutter test test/retrieval_cosine_test.dart` — ranking and tie-break checks pass.
- `flutter analyze lib/retrieval/cosine_search.dart test/retrieval_cosine_test.dart` — clean.
- `flutter test test/retrieval_hybrid_test.dart` — agreement ranking and empty-limit behavior pass.

Remaining work: wire cited source navigation and measure corpus latency/memory gates.
