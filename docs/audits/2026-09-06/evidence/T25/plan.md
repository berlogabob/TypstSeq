# T25 profile harness preparation

Date: 2026-09-09
Status: harness prepared; device/profile validation pending (task remains incomplete).

Added `integration_test/sync_dashboard_saf_profile_test.dart`. The Android-only harness fails closed unless the active registry entry is the exact `android-tree` / `TyLogAuditVault` fixture with persisted access and `README-AUDIT.txt == "TyLogAuditVault\\n"`. It backs up and restores `.tylog/sync_trace.jsonl`, writes 200 valid deterministic JSONL events, models the dashboard's 500 ms single-flight `exists` + `readText` + parse reload for 60 seconds, and prints reload counts, probes, full-read bytes, load/parse p50/p95/max, and 16 ms ticker frame gaps.

Static checks:

- `dart format integration_test/sync_dashboard_saf_profile_test.dart` — clean.
- `flutter analyze integration_test/sync_dashboard_saf_profile_test.dart` — no issues.
- `git diff --check` — clean.
- `graphify update .` — completed.

Fingerprint: `f538dc3c1abb18e188247ed3686f8a50160ac86078bccd2b0840570e467768a7`.

No device/profile runner was executed.
