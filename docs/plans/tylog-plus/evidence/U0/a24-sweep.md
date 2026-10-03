# U0 integration sweep on the A24 (2026-10-03)

`flutter test <file> -d 000251565001005` per file (debug package `.debug`, production
app untouched), at commit 2d5cd9d. Same exclusions as the P30 sweep: P21/P23 (handshake
script), graph_share/share_pdf (system chooser), and the real-vault drive. An empty
result column means the test skipped itself for a missing define or private input.

```
0 +1 ~1: All tests passed! markdown_import_native_test.dart
0 +1: All tests passed! nextcloud_sync_native_test.dart
0  p05_embedding_profile_test.dart
0 +1: All tests passed! p05_exact_search_profile_test.dart
1 +0 -1: Some tests failed. p05_resume_profile_test.dart
0  p12_editor_frame_native_test.dart
0  p12_editor_render_trace_native_test.dart
0 +1: All tests passed! p12_editor_save_native_test.dart
0 +1: All tests passed! p12_latency_native_test.dart
0  p12_virtual_plain_frame_native_test.dart
0 +1: All tests passed! p22_graph_latency_native_test.dart
0  p22_private_graph_native_test.dart
0 +4: All tests passed! pdf_reader_native_test.dart
0 +1: All tests passed! pdf_reader_review_native_test.dart
0  pkms_native_test.dart
0  private_pdf_corpus_test.dart
0 +1: All tests passed! rich_editor_native_test.dart
1 +0 -1: Some tests failed. saf_contention_profile_test.dart
0 +1: All tests passed! sync_attribution_test.dart
1 +0 -1: Some tests failed. sync_dashboard_saf_profile_test.dart
0 +1: All tests passed! sync_foreground_native_test.dart
0 +1: All tests passed! vault_worker_attribution_test.dart
0 +1: All tests passed! vault_worker_jank_test.dart
0 +3: All tests passed! vault_worker_native_test.dart
1 +0 -1: Some tests failed. vault_worker_saf_shutdown_test.dart
0 +1: All tests passed! vault_worker_saf_test.dart
0  vfs_base_files_bench_test.dart
```

All four failures are setup-gated, confirmed by rerunning each: `p05_resume_profile_test`
needs `P05_RESUME_PHASE=interrupt|resume`; the three SAF tests throw
`Bad state: No element` from `VaultRegistry.active` because the debug package has no SAF
vault. No app bugs. The PDF reader crash the P30 found (c2776f7) passes here (+4).
The P12 frame gates ran separately as profile builds ([P12e/a24-window.md](../P12e/a24-window.md)).
