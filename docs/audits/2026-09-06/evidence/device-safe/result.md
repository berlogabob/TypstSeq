# Safe Android profile checks

Date: 2026-09-09
Device: `000251565001005`
Build mode: Flutter profile, installed with `flutter drive`.

- `sync_attribution_test.dart`: **2 passed**. The real-vault-scale probe reported 2,061 paths, 532 KB encoded state, 8 ms one-checkpoint copy/encode, 1,083 ms for 206 checkpoints, and 7 ms trace flush. Log: `sync_attribution.log`.
- `vault_worker_saf_test.dart`: test driver reported **2 passed**, including `SAF-PROBE answered: hasAccess=false`; after teardown Android emitted a fatal zygote/JNI error: `Failed to mount /data_mirror/data_de/null/0/org.tylog.tylog`. Log: `vault_worker_saf.log`.
- `sync_foreground_native_test.dart` with `TYLOG_FOREGROUND_HOLD_SECONDS=5` and `--keep-app-running`: **2 passed**. Package verification succeeded via `adb shell pm path org.tylog.tylog`. Logs: `sync_foreground_native.log`, `sync_foreground_native_pm_path.log`.
- `share_pdf_native_test.dart` with `--keep-app-running`: **2 passed, 4 failed**. Four report tests failed before compilation because the installed Dart/Rust bridge content hashes were out of sync (`873011556` vs `618104202`). Package verification still succeeded. Logs: `share_pdf_native.log`, `share_pdf_native_pm_path.log`.

Execution stopped on the share-PDF bridge-hash failure. No vault was selected or modified, and no product/test code was edited.
