# P21 progress — vector retrieval primitive

Status: RUNNING

Added bounded cosine top-K over stored Float32-compatible BLOBs. Scores are normalized, malformed dimensions are skipped, and equal scores sort by stable chunk ID. This keeps the query interface independent of whether vectors come from the brute-force isolate or a future sqlite-vec backend.

Evidence:

- `flutter test test/retrieval_cosine_test.dart` — ranking and tie-break checks pass.
- `flutter analyze lib/retrieval/cosine_search.dart test/retrieval_cosine_test.dart` — clean.

Remaining work: fuse FTS5 and vector candidates, add cited source navigation, and measure corpus latency/memory gates.
