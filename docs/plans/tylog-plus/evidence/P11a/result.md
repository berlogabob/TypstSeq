# P11a/P11b — durable note edits

Status: PASS (host)

Editor saves and the shared closed-note mutation path now write the vault file
and its graph node, immutable parented revision, outbox entry, and derived
invalidation as one user-visible operation. Existing task, status, rating,
repair, and autolink actions already use that shared mutation path.

Each vault owns a separate SQLite database, so equal note IDs in different
vaults cannot overwrite each other. The legacy `tylog.db` is claimed by the
first existing vault; later vaults use deterministic hashed filenames.
Revision parent selection and commit share one transaction, with monotonic
timestamps when the device clock repeats or moves backward.

The database stores the exact bytes written by `Vault.saveNote`. If the
database transaction fails, the previous file bytes are restored and the
editor remains dirty with a save error. Writes to the same path are serialized,
and both path mapping and parent lookup read only their newest matching row.
Disposable-note and article deletion keep immutable history through a tombstone
revision. Opening a note retries if a closed-note mutation overlaps its read.

Run:

```text
flutter analyze lib/database/note_persistence.dart \
  lib/workspace_controller.dart lib/app_mobile.dart \
  test/database/note_persistence_test.dart test/workspace_controller_test.dart
No issues found

flutter test
676 tests passed; 2 opt-in tests skipped
```

An independent Luna review found and verified fixes for cross-vault identity,
revision ordering, deletion, rollback marker state, missing-file deletion, and
read/mutation races. Creation/import routing remains P11c.
