Fix a bug in ONE file, packages/tylog_core/lib/src/scanner.dart (about 2,800 lines). Do not modify or create any other file, and do not edit any test. Make a targeted edit; do not rewrite the file.

Symptom: on every app launch the whole vault is re-derived (minutes of work) although nothing changed. The scanner keeps a local index cache per note and can also reuse "donor" index entries published by other devices. When an unchanged note has BOTH a current local cache entry and a donor entry written by an older index/query version, the scanner prefers the stale donor, decides the entry is outdated and re-derives the note. It should prefer the current, unchanged local cache entry; a donor is only for notes the local cache cannot serve.

Failing tests that describe the required behaviour are in packages/tylog_core/test/scanner_cache_test.dart (names contain "current local cache beats donor" and "old donor is re-derived once"). Read them first.

Done when `cd packages/tylog_core && dart test test/scanner_cache_test.dart` passes, without breaking any other test in that package.
