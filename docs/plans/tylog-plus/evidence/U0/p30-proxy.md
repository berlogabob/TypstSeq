# U0 integration sweep on the Huawei P30 (proxy, 2026-09-29)

`flutter test <file> -d <P30>` per file (debug package `.debug`, production app
untouched), at commit aa76d0f. Excluded: the real-vault drive, P21/P23 (these need
the handshake script), and graph_share/share_pdf (they open the system chooser, which
blocks every later test until a human dismisses it). An empty result column means
the test skipped itself for a missing define or private input.

```
0 +1 ~1: All tests passed integration_test/markdown_import_native_test.dart
0 +1: All tests passed integration_test/nextcloud_sync_native_test.dart
0  integration_test/p05_embedding_profile_test.dart
0 +1: All tests passed integration_test/p05_exact_search_profile_test.dart
1 +0 -1: Some tests failed integration_test/p05_resume_profile_test.dart
0  integration_test/p12_editor_frame_native_test.dart
0  integration_test/p12_editor_render_trace_native_test.dart
0 +1: All tests passed integration_test/p12_editor_save_native_test.dart
0 +1: All tests passed integration_test/p12_latency_native_test.dart
0  integration_test/p12_virtual_plain_frame_native_test.dart
0 +1: All tests passed integration_test/p22_graph_latency_native_test.dart
0  integration_test/p22_private_graph_native_test.dart
1 +2 -2: Some tests failed integration_test/pdf_reader_native_test.dart
0 +1: All tests passed integration_test/pdf_reader_review_native_test.dart
0  integration_test/pkms_native_test.dart
0  integration_test/private_pdf_corpus_test.dart
0 +1: All tests passed integration_test/rich_editor_native_test.dart
1 +0 -1: Some tests failed integration_test/saf_contention_profile_test.dart
0 +1: All tests passed integration_test/sync_attribution_test.dart
1 +0 -1: Some tests failed integration_test/sync_dashboard_saf_profile_test.dart
0 +1: All tests passed integration_test/sync_foreground_native_test.dart
0 +1: All tests passed integration_test/vault_worker_attribution_test.dart
0 +1: All tests passed integration_test/vault_worker_jank_test.dart
0 +3: All tests passed integration_test/vault_worker_native_test.dart
1 +0 -1: Some tests failed integration_test/vault_worker_saf_shutdown_test.dart
0 +1: All tests passed integration_test/vault_worker_saf_test.dart
0  integration_test/vfs_base_files_bench_test.dart
```

Failures:
- `pdf_reader_native_test`: **app bug**. A TextEditingController is used after
  dispose, and then the Overlay `_dependents.isEmpty` assertion fires.
- `saf_contention`, `sync_dashboard_saf`, `vault_worker_saf_shutdown`: setup-gated,
  not bugs. `VaultRegistry.active` has no entry because the debug package has no SAF vault.
- `p05_resume_profile_test`: needs `P05_RESUME_PHASE=interrupt|resume`.
