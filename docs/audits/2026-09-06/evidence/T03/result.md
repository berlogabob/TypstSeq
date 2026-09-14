Task: T03
Status: DONE

The failure-path regression now sequences the replaced scan gate completer correctly and passes. The catch publishes the sync error before conflict/index maintenance and refreshes only when local content changed. Rename replacement and old-key deletion are attributed as local content changes; device metadata remains excluded.

Checks:
- Focused suites: 146 tests passed (`vault_worker_test.dart`, `nextcloud_sync_test.dart`, `workspace_controller_test.dart`).
- Targeted `flutter analyze` on all T03 files: no issues.
- Scoped diff SHA256 (`git diff -- lib/workspace_controller.dart lib/nextcloud_sync.dart lib/nextcloud_sync/path_sync.dart test/workspace_controller_test.dart test/nextcloud_sync_test.dart test/vault_worker_test.dart`): `5a59e5085b92fef0f1efd0233ddea60e27441e9f7fa53b35188c6a3674e1fdd1`.

Coordinator accepted 2026-09-08 after reviewing download/delete/rename notifications and error-first catch; 146 focused tests passed and scoped analysis clean.
