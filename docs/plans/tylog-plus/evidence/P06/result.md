# P06 — native database bootstrap and migration

Date: 2026-09-15. Status: PASS.

TyLog now has an app-private Drift database foundation backed by native SQLite. Every custom/default file connection uses `NativeDatabase.createInBackground`, configures WAL, enables foreign-key enforcement, and sets a 5,000 ms busy timeout. The database is not connected to app startup or production-vault import yet.

Schema version 2 contains one internal metadata table. The tested version-1 migration adds its timestamp column and preserves existing rows; unsupported version changes fail instead of rebuilding data.

## Verification

```bash
flutter test test/database/tylog_database_test.dart
flutter analyze lib/database/tylog_database.dart test/database/tylog_database_test.dart
flutter build apk --profile
adb install -r build/app/outputs/flutter-apk/app-profile.apk
```

- Eight native checks passed: creation, schema/table access, WAL, foreign keys, busy timeout, v1-to-v2 data preservation, idempotent reopen, and unsupported-version rejection.
- Focused analysis reported no issues.
- The full Flutter suite passed: 607 tests, with one existing skipped test.
- Android profile APK built successfully and installed over the production package without clearing data.
- On A024 cold launch, the real vault remained selected, no audit marker appeared, and the cached rebuild notice cleared within the observation window.

Claude Haiku `claude-haiku-4-5-20251001` drafted the database and tests; its CLI did not report token/cost totals. Codex `gpt-5.6-luna` independently reviewed the final coordinator-corrected implementation and returned PASS; provider usage was unavailable.
