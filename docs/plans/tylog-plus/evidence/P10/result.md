# P10 — portable export and conflict-aware re-import

Status: PASS (host)

TyLog now exports a deterministic ZIP containing exact source, node, edge and
immutable revision rows plus every portable vault file. The manifest pins the
format and database schema and records SHA-256 and size for every payload.
Import validates the complete archive before planning changes.

Stable IDs classify rows and vault paths as insert, unchanged or conflict.
Divergent data is returned with both payloads and is never overwritten. A clean
apply inserts sources, nodes, edges and parent-ordered revisions in one database
transaction. A failed vault write rolls back database rows and deletes files
created by that attempt. Historical snapshot revisions are not placed in the
outbox.

The host rehearsal preserves two linked nodes, annotation attributes, a source,
three parent-linked revisions, bibliography bytes and an attachment hash. A
second import is a no-op; a divergent node produces exactly one conflict.

Run:

```text
flutter test test/database/portable_snapshot_test.dart \
  test/database/portable_merge_test.dart \
  test/database/portable_roundtrip_test.dart
11 tests passed

flutter analyze lib/database/portable_snapshot.dart \
  lib/database/portable_merge.dart lib/database/portable_import.dart \
  test/database/portable_snapshot_test.dart \
  test/database/portable_merge_test.dart \
  test/database/portable_roundtrip_test.dart
No issues found

flutter test
663 tests passed; 2 opt-in tests skipped
```

The shared vault path validator rejects dot-segment/control aliases, archive
validation rejects case-fold collisions, and device-local `.tylog/` state is
excluded. An independent Luna review found these issues before acceptance and
verified their fixes with the focused 18-test run.

The current codec assembles ZIP bytes in memory. P24 must measure real export
memory before production migration; switch to the existing archive stream API
only if that measurement exceeds the mobile memory gate. UI routing belongs to
P11.
