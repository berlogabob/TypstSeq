# T26 profile harness preparation

Date: 2026-09-09
Status: harness prepared; device/profile validation pending (task remains incomplete).

Added `integration_test/saf_contention_profile_test.dart`. The test is Android-only and fails closed unless the active registry entry is `android-tree`, named exactly `TyLogAuditVault`, has a persisted SAF grant, and the exact coordinator marker `README-AUDIT.txt == "TyLogAuditVault\\n"` is present. It mutates only `.tylog/device-audit/`, creates 30 deterministic notes, records exactly 30 one-note read+atomic-save samples for idle and 30 for contention, and verifies final bytes, hashes, and decoded content. Contention writes a deterministic 8 MiB attachment three times, reports total transfer bytes (24 MiB), transfer duration, and the number of contended samples that observed the transfer active.

Static validation:

- `dart format integration_test/saf_contention_profile_test.dart` — clean.
- `flutter analyze integration_test/saf_contention_profile_test.dart` — no issues.
- `git diff --check` — clean.
- `graphify update .` — completed.

Fingerprint: `ab72910d6daa502ff922ca68c11ed10daa8824a8a697f56301054c18472fb9fe`.

Pending device command (not run here): profile `flutter drive` with `--keep-app-running` and the production `TyLogAuditVault` grant plus coordinator marker.
