# P17 — snapshot bootstrap and recovery

Status: DONE (host)

The existing snapshot and sync paths meet the bounded recovery contract. Portable snapshot validation rejects unlisted archive entries and preserves only portable vault files. Interrupted bootstrap writes a resumable checkpoint while retaining the corrupt prior state for inspection. A 1,602-file remote restore uses one archive download after two listings and restores all files without per-file GETs.

Evidence:

- `flutter test test/database/portable_snapshot_test.dart test/database/portable_roundtrip_test.dart` — snapshot validation and round-trip checks pass.
- `flutter test test/nextcloud_sync_test.dart` — interrupted recovery, corrupt-state replacement, archive restore, and ZIP fallback checks pass.
- Scale gate: the 1,602-file restore asserts two PROPFINDs, one ZIP GET, zero individual GETs, and verifies the final file.

The portable codec remains memory-backed; P24 is the planned production measurement before very large exports. No new snapshot format is needed for this milestone.
