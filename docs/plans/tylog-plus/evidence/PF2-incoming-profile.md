# PF2 Incoming queue profile (2026-11-05)

Device: Huawei P30, Android, adb serial `XPH0219904001750`. Ran
`integration_test/pf2_incoming_profile_test.dart` using the `.profiletest`
application suffix (`org.tylog.tylog.profiletest`); the production package and
vault were not targeted. The Mac screen was locked, so no GUI profiling or SAF
picker interaction was attempted.

The harness used app-private local storage and production audio/OCR queue
loaders. Each density had 1,000 audio JSON sidecars plus 100 OCR mounts, one
review row per mount. Sparse audio had 10 actionable and 990 rejected rows;
dense audio had 1,000 actionable rows. It loaded the first audio and OCR
pages, requested Show older for audio, appended accepted audio and OCR
decisions, refreshed the audio page from its updated snapshot, rendered the
visible audio and OCR rows, and collected Flutter frame timings. One profile
run; results are diagnostic, not thresholds.

| Fixture | Audio first | OCR first | Show older audio | Audio refresh | Rows: audio first / older / after decision; OCR first / after decision | Decision load | Dart heap delta | Process RSS delta |
| --- | ---: | ---: | ---: | ---: | --- | ---: | ---: | ---: |
| Sparse | 1,668 ms | 229 ms | 367 ms | 305 ms | 10 / 0 / 9; 20 / 20 | 7 ms; 1 read, 94,950 bytes | +1,472,320 bytes | +18,743,296 bytes |
| Dense | 1,908 ms | 326 ms | 512 ms | 426 ms | 20 / 20 / 20; 20 / 20 | 1 ms; 0 reads | +1,099,488 bytes | +27,590,656 bytes |

Each first queue load read 1,000 audio sidecars and 100 OCR row files (1,100
stream reads, 89,050 bytes); metadata checks included 200 stats. Cached Show
older did zero sidecar reads. Appending the two decisions used one directory
create and two ledger appends. Refresh listed the audio sidecar directory but
read no sidecars. Four rendered-frame `totalSpan` samples were 30.808, 44.450,
7.505, and 16.239 ms. These are individual scheduler samples, not sustained
build/raster percentiles. Heap came from VM service; RSS includes native
memory. Fixture creation and app cold-start are outside queue timings.

## P30 SAF-backed queue loader slice (2026-11-05)

Huawei P30 (`XPH0219904001750`), Android profile build, installed and run only
as `org.tylog.tylog.profiletest` with `PF2_SAF_ONLY=true`. The selected tree
was the dedicated `Downloads/PF2-profile-fixture`; it held 50 audio JSON
sidecars and 25 OCR rows (6,874 bytes read during the measured first page).
No production package or vault was targeted. The harness writes fixture data
through `AndroidTreeVaultStorage` and cleans up those files and directories in
teardown.

| Measurement | Result |
| --- | ---: |
| Audio/OCR first pages | 20 / 20 rows |
| First queue load | 574 ms |
| First load storage operations | 4 lists, 53 stats, 51 reads, 6,874 bytes |
| Show older audio | 20 rows, 19 ms, 2 lists, 0 stats, 0 reads |
| Decision write | 1 ledger append; refreshed page retained 20 rows |
| Retained Dart heap delta | +91,152 bytes |
| Rendered list frame `totalSpan` samples | 50.690 ms, 16.217 ms |

These are single diagnostic samples, not percentiles. Frame timings are for a
profile `ListView` of the returned queue rows; they do not represent opening
the actual Incoming bottom sheet. The harness does not measure enrichment
mention computation, actual sheet readiness, or actual sheet decision and
Show older interaction. Those measurements remain in
PF2-rest-rest-rest-rest-rest-rest. Device RSS and native SAF provider query
counts were not measured; the storage operation counts are Dart calls into
the SAF bridge.

## Actual Incoming sheet harness (2026-11-05)

Added `integration_test/pf2_incoming_sheet_profile_test.dart`. It mounts the
production `TyLogApp` in the isolated profile package, requires its already
registered Android-tree vault, opens the real Incoming sheet, and records
readiness time, visible mention/audio/OCR rows, sheet frame timings, retained
Dart heap and RSS. It also times Show older and an OCR accept when those
controls are present. It does not synthesize sidecars or select a folder.

The P30 run was attempted with
`flutter drive --no-pub --no-dds --profile -PtylogProfileSuffix=.profiletest
-d XPH0219904001750 --driver=test_driver/integration_test.dart
--target=integration_test/pf2_incoming_sheet_profile_test.dart`. The APK built,
but Android rejected its install because its signing certificate did not match
the installed `.profiletest` package. Flutter's fallback removed that package;
the saved app registration and SAF grant are now gone. The selected SAF tree
was not modified, and the production package was not targeted. ADB confirmed
the production package still has `firstInstallTime=2026-11-05 15:27:02`.
No actual-sheet numbers were collected. Reinstalling and selecting the exact
existing copy again must happen before this harness can run; do not select or
modify a vault while the intended copy is uncertain.
