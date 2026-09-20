# P20 progress — deterministic chunking

Status: RUNNING

Added deterministic text chunking keyed by source-version ID. Each chunk carries source character offsets, configurable overlap, and a SHA-256 content hash; unchanged source versions therefore produce stable chunk IDs and changed ranges can be re-embedded independently.

Evidence:

- `flutter test test/retrieval_chunking_test.dart` — 2 passed.
- `flutter analyze lib/retrieval/chunking.dart test/retrieval_chunking_test.dart` — clean.

Remaining work: persist chunks, add resumable embedding job states, and connect the pinned offline runtime from P05.
