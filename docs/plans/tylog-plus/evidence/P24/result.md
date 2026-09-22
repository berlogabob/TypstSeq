# P24 — migration rehearsal and integrated failures

Status: RUNNING

The failure-path suite exercises schema migration and rollback, atomic vault migration, permission loss, stalled storage calls, interrupted sync, resumable recovery, corrupt-state replacement, archive restore, and regression behavior. The complete Nextcloud sync suite also covers conditional-transfer races, remote wipe protection, conflict preservation, and the 1,602-file archive restore path.

Evidence:

- `flutter test test/database/tylog_database_test.dart test/database/tylog_graph_schema_test.dart test/vault_storage_test.dart test/import/legacy_import_10k_rehearsal_test.dart` — 25 passed, 1 skipped.
- `flutter test test/nextcloud_sync_test.dart` — 105 passed.

The tests use deterministic failure injectors and local WebDAV fixtures; P25 still requires release builds, the real vault, and both physical devices.

On 2026-09-22 the Android profile seed → `adb shell am force-stop` → reopen
sequence passed for the PDF annotation database. The accepted rerun kept the
seed process alive before force-stop so its file-backed SQLite state was
available to the reopened process.

Acceptance correction (2026-09-20): existing unit evidence does not close the full milestone. See the execution ledger for remaining integration and native checks.

## Native post-commit restart evidence (2026-09-20)

A24, isolated `org.tylog.tylog.debug` test package, generated one-page PDF.

1. `flutter test --no-pub --no-uninstall integration_test/pdf_reader_native_test.dart -d <A24>` seeds a file-backed SQLite DB and verifies native selection/save/reopen/navigation.
2. `adb shell am force-stop org.tylog.tylog.debug` terminates the test app.
3. `flutter test --no-pub --no-uninstall integration_test/pdf_reader_native_test.dart -d <A24> --dart-define=P24_REOPEN_ONLY=true` asserts saved quote/version exist before rendering, then repeats navigation.

Both runs pass (one native test each). `--no-uninstall` is necessary because Flutter otherwise removes the test app/data on exit. Reopen waits for PDF controller readiness independently of persisted data. Production package/data were not used. This establishes post-commit restart recovery for annotations, not interruption midway through migration, disk-full behavior, or the complete P24 release gate.

Final host regression: `flutter test --no-pub` — 729 passed, 2 skipped. Native integration testing had cached Vulkan test shaders; removing only generated `build/unit_test_assets/AssetManifest.bin` rebuilt them for the host SkSL backend. No application workaround was needed. Run host and device asset-building tests sequentially.

## Host failure-rehearsal rerun (2026-09-21)

The focused migration/import failure suite passed **25 tests with 1 skipped**;
the full local-WebDAV sync failure suite passed **105 tests**. This rerun covers
schema rollback, permission loss, stalled storage, interrupted import/sync,
resumable recovery, conflict preservation, and the 1,602-file archive restore.
Physical-device interruption and production-release rehearsal remain open.

Sequential host rerun passed 130 migration, rollback, storage, import, and
local WebDAV failure/sync tests with 1 expected skip. Physical process-death
and real Nextcloud release rehearsal remain open.

P24d adds the controller-level restart-boundary matrix: 19 tests passed for
cold-index donor ordering, vault switching during sync, retry/backoff, polling
gates, conflict recovery, and post-sync reindex routing. These model restart
boundaries in-process; actual process kill remains device-gated.
