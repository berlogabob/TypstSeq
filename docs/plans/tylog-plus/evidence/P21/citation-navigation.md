# P21 cited navigation host seam

The existing generic chunk navigation query keeps returning source/version
offsets for every source kind. A separate PDF citation lookup resolves an
extracted PDF chunk to its source kind, vault-relative locator, title,
immutable source-version ID, content, and UTF-16 character range. That PDF-only
lookup skips missing sources, unsupported extraction versions, non-PDF sources,
and ranges that do not match the stored chunk text.

`KnowledgeScreen` accepts optional cited search results and an open-citation
callback; regular FTS results keep their existing behavior. The PDF reader can
open a citation only when the newly extracted source-version ID exactly matches
the cited version. It navigates to the page and selects the cited text range,
clipped at a page boundary.

Host checks: `flutter test test/knowledge_screen_test.dart
test/database/chunk_persistence_test.dart test/pdf_extraction_test.dart` and
targeted `flutter analyze` pass. The integrated `flutter test --no-pub` suite
passed 754 tests with two expected skips. This adds the UI/navigation seam only; no query
embedder or model assets are wired, and Android model quality, latency, and
memory acceptance still require the device.
