# P24 — migration rehearsal and integrated failures

Status: DONE (host)

The failure-path suite exercises schema migration and rollback, atomic vault migration, permission loss, stalled storage calls, interrupted sync, resumable recovery, corrupt-state replacement, archive restore, and regression behavior. The complete Nextcloud sync suite also covers conditional-transfer races, remote wipe protection, conflict preservation, and the 1,602-file archive restore path.

Evidence:

- `flutter test test/database/tylog_database_test.dart test/database/tylog_graph_schema_test.dart test/vault_storage_test.dart test/import/legacy_import_10k_rehearsal_test.dart` — 25 passed, 1 skipped.
- `flutter test test/nextcloud_sync_test.dart` — 105 passed.

The tests use deterministic failure injectors and local WebDAV fixtures; P25 still requires release builds, the real vault, and both physical devices.
