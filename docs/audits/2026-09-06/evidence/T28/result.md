# T28 device closure evidence

Date: 2026-09-09
Status: DEVICE VALIDATED WITH LIMITATIONS

The guarded Android profile checks completed on the disposable `TyLogAuditVault` fixture. T00 cold-start evidence covered 2,001 entries: the first populated scan reached completion at 54 seconds; repeat cold display launches measured 440 ms and 633 ms, and the final normal launch measured 894 ms. The five-minute idle run lasted 303 seconds with unchanged index/search metadata, a live process, and no fatal error.

Device checks passed:

- T26: 60 idle/contended SAF mutations with final byte/hash/content integrity; attachment contention measurements recorded separately.
- Foreground-service profile test: 2 passed.
- PDF profile suite after native rebuild: 6 passed.
- Worker native profile suite: 4 passed in 39 seconds.
- Final rich-editor Magic profile test: 2 passed in 31 seconds after correcting harness focus, lazy-scroll, and real-IME assumptions.

T04's controlled 401/403 regression verifies one rejected-credential request and zero repeated automatic setup/resume/autosave attempts until credentials change or explicit retry. No real Nextcloud account was configured on the disposable fixture.

An authentic pre-fix phone timing baseline does not exist, so no before/after percentage claim is made. The unchanged-index idle run and successful device checks provide post-fix validation only.

An early `flutter drive` run without `--keep-app-running` uninstalled app-local data. The external production `TyLog` folder was untouched; the user may need to restore app settings and reselect the vault.
