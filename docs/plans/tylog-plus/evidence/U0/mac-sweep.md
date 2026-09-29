# U0 macOS integration sweep (2026-09-29)

`make verify` 29-file integration loop, run in two parts (the first part was
interrupted for machine priority). Part 1 (22ba98c): the first 11 files through
p12_virtual_plain_frame passed. Part 2 (c2776f7), each file with a 900 s cap, where an
empty result means the test skipped itself for a missing private input:

```
0 +1: All tests passed integration_test/p22_graph_latency_native_test.dart
0  integration_test/p22_private_graph_native_test.dart
0 +4: All tests passed integration_test/pdf_reader_native_test.dart
0 +1: All tests passed integration_test/pdf_reader_review_native_test.dart
0 +1: All tests passed integration_test/pkms_native_test.dart
0  integration_test/private_pdf_corpus_test.dart
0 +1: All tests passed integration_test/rich_editor_native_test.dart
0  integration_test/saf_contention_profile_test.dart
0 +5: All tests passed integration_test/share_pdf_native_test.dart
0 +1: All tests passed integration_test/sync_attribution_test.dart
0  integration_test/sync_dashboard_saf_profile_test.dart
0  integration_test/sync_foreground_native_test.dart
0 +1: All tests passed integration_test/vault_worker_attribution_test.dart
0 +1: All tests passed integration_test/vault_worker_jank_test.dart
0 +3: All tests passed integration_test/vault_worker_native_test.dart
0  integration_test/vault_worker_saf_shutdown_test.dart
0  integration_test/vault_worker_saf_test.dart
0  integration_test/vfs_base_files_bench_test.dart
```

No failures. The host `flutter test` and `flutter analyze` are clean (analyzer fix
22ba98c). P21/P23 native tests pass separately (see P21/proxy-runs.md). The release
builds are recorded below once they finish.
