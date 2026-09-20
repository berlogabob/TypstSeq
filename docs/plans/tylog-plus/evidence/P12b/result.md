# P12b — non-blocking startup cache

Status: PASS (host)

Production startup uses the worker isolate as the owner of the cached index.
The root isolate now skips `_index/index.json` decoding and publishes the vault
and today note before background indexing. In-process callers retain the warm
cache path used by tests and tooling.

The gated-read regression places a valid vault marker and a blocked cached-index
read on storage. Startup completes with the editor note available and no index
read on the root path; releasing the gate lets the background rebuild publish
the index normally.

```text
flutter test test/workspace_controller_test.dart \
  --plain-name 'worker startup does not decode the cached index on the root isolate'
1 test passed

flutter test
682 tests passed; 2 opt-in tests skipped

flutter analyze lib/workspace_controller.dart test/workspace_controller_test.dart
No issues found
```

True SQLite keyset pages and list-surface migration remain P12c–d.
