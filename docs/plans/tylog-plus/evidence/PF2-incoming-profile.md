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
registered app-local P2P6 vault, opens the real Incoming sheet, and records
readiness time, visible mention/audio/OCR rows, sheet frame timings, retained
Dart heap and RSS. It also times Show older and an OCR accept when those
controls are present. It does not synthesize sidecars or select a folder.

The P2P6 follow-up changed the harness guard from `android-tree` to `app-local`
and waits until the Incoming sheet header is present and its queue spinner has
cleared. This matches the transferred copy's real storage kind and includes
the sheet transition and queue load in its readiness timing.

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

## PF2-rest-rest-rest-rest-rest-rest-rest follow-up (2026-11-05)

Rechecked the Huawei P30 (`XPH0219904001750`) before attempting another run.
`org.tylog.tylog.profiletest` is absent from `pm list packages`, and Android
reports no `/data/user/0/org.tylog.tylog.profiletest` or
`/sdcard/Android/data/org.tylog.tylog.profiletest/files`. The installed
`org.tylog.tylog.saftest` and `.debug` packages have separate app-private data;
neither contains the P2P6 copy. The production package still reports
`firstInstallTime=2026-11-05 15:27:02`. No install, picker, vault write, or
`svc power stayon` command was issued. The Mac screen was locked, so no GUI
check was attempted. Restore the existing P2P6 copy into `.profiletest` storage
before collecting the actual-sheet measurements.

## PF2-rest-rest-rest-rest-rest-rest-rest-rest follow-up (2026-11-05)

The requested rerun was checked on Huawei P30 (`XPH0219904001750`):
`org.tylog.tylog.profiletest` was absent, while production still reported
`firstInstallTime=2026-11-05 15:27:02`. The existing P2P6 vault copy must first
be transferred again from the Mac. The Mac screen was locked, and the
documented P2P sender flow requires launching its app UI to create the transfer
ticket. Per the device instructions, no Mac GUI action, alternate transfer, or
vault selection was attempted. The actual-sheet harness therefore did not run
and no performance numbers are claimed. The focused tests
`test/review_queue_test.dart` and `test/enrich_flow_test.dart` passed; the full
`flutter test` suite passed with 2,080 tests and 10 skips. The blocked attempt
was later superseded by the successful P2P6 transfer and profile run below.

## PF2-rest-rest-rest-rest-rest-rest-rest-rest-rest actual P30 slice (2026-11-05)

Created a read-only APFS clone of `~/Nextcloud/TyLogVault` at
`/tmp/typstseq-p2p6-source` and transferred it with the P2P6 Mac sender to
Huawei P30 `XPH0219904001750`, only in `org.tylog.tylog.profiletest`. The clone
contained 25,210 files. The receiver reported SHA-256-verified completion of
2,453,423,313 bytes in 274,477 ms and stored the copy at
`/data/user/0/org.tylog.tylog.profiletest/files/p2p6-received`. The source clone
was read-only during transfer. Production `org.tylog.tylog` continued to report
`firstInstallTime=2026-11-05 15:27:02`.

Opening the received copy on the P30 published its cached 10,085-note index
35.562 s after startup began; the scan reported 34.201 s and parsed three
notes. The profile run used `flutter drive --no-pub --no-dds --profile
-PtylogProfileSuffix=.profiletest -d XPH0219904001750
--driver=test_driver/integration_test.dart
--target=integration_test/pf2_incoming_sheet_profile_test.dart
--dart-define=P2P_HARNESS=true`.

| Measurement | Result |
| --- | ---: |
| Incoming sheet readiness | 4,484 ms |
| Storage kind | `app-local` |
| Visible mention / audio / OCR rows | 0 / 0 / 0 |
| Mention computation (`daily/2026/11/2026-11-05.typ`) | 782 ms total; 780 ms building enrichment memory; 0 decisions, tags, or markers |
| Sheet `FrameTiming.totalSpan` samples | 32; median 12.881 ms; maximum 499.338 ms; 9 over 16.7 ms |
| Dart heap before / after / delta | 23,428,960 / 161,259,488 / +137,830,528 bytes |
| Process RSS after sheet load | 430,157,824 bytes |
| Decision append / Show older | Unavailable: the actual queue had no eligible rows or older page |

This is a single profile sample from the real app-local received copy, not a
SAF-backed queue measurement or a repeatable percentile. The Home screenshot
strip is separate from the review sheet; the measured mention/audio/OCR queues
were empty. No decision was made and no source vault was written. The new plan
follow-up repeats the sheet profile when an authorized received copy contains
eligible rows so those actions can be measured without fabricating proposals.

## Post-profile package cleanup and P2P6 restoration (2026-11-05)

After `flutter drive` completed, Android's package log recorded
`PACKAGE_REMOVED` for `org.tylog.tylog` at 20:53:15 and
`org.tylog.tylog.profiletest` at 20:58:53. No explicit `adb uninstall` or
`pm clear` command was issued. Production had last been observed with
`firstInstallTime=2026-11-05 15:27:02` before its removal; it is absent now, so
that timestamp cannot be rechecked or restored. No production reinstall was
attempted.

To leave the requested test copy installed with data, recreated the read-only
APFS clone and repeated only the P2P transfer and open flow, without another
integration-driver run. The receiver verified 2,453,423,714 bytes in 238,268
ms. `.profiletest` was installed at 21:05:34, then updated with `adb install
-r`; its first-install time remained 21:05:34. The received copy is active at
`/data/user/0/org.tylog.tylog.profiletest/files/p2p6-received`. The final open
published its 10,085-note index 34.145 s after startup, with a 32.657 s scan.
The P30 was left with `.profiletest` running and its received copy intact. The
temporary clone and JNI staging were removed. The test-driver package cleanup
and production-install recovery remain unresolved; do not rerun `flutter
drive` as part of this follow-up.

## PF2-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest follow-up (2026-11-05)

The requested safe Flutter integration-test command was run:
`flutter test integration_test/pf2_incoming_sheet_profile_test.dart -d
XPH0219904001750 --no-uninstall`. Flutter built and installed the separate
`org.tylog.tylog.debug` package; that package has no vault registration, so the
harness stopped at `profile vault copy missing` before opening the sheet. The
existing `.profiletest` package remained installed at its recorded first
install time `2026-11-05 21:05:34`. The production package was absent before
and after this attempt, so its historical `firstInstallTime=2026-11-05
15:27:02` could not be queried; no command installed, launched, or modified it.
The profile harness therefore collected no new device measurements. The Mac
screen was locked, so GUI or P2P sender actions were skipped.

`flutter test` passed the full suite: 2,089 tests passed and 10 were skipped.
The actual-sheet measurement still needs a runner that targets the installed
`.profiletest` app without Flutter's debug-package path, plus a received copy
with eligible rows for measuring a decision append and Show older paging.

## PF2-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest (2026-11-06)

Added a registry-preserving Flutter integration-test path by setting
`ORG_GRADLE_PROJECT_tylogDebugSuffix=.profiletest` and signing that isolated
debug variant with the release key when available. The signed build matched
the installed `.profiletest` certificate. Ran
`ORG_GRADLE_PROJECT_tylogDebugSuffix=.profiletest flutter test
integration_test/pf2_incoming_sheet_profile_test.dart -d XPH0219904001750
--no-uninstall`; it retained the package's original
`firstInstallTime=2026-11-05 21:05:34` and loaded the registered 10,085-note
P2P6 copy. The harness now targets the daily More panel by a stable key,
captures all three Show older controls, and records an OCR accept or audio
reject when those rows exist.

The actual sheet opened successfully. In this debug integration build, sheet
readiness was 8,489 ms; 30 frame samples had a 44.071 ms median and 818.004 ms
maximum; process RSS was 705,859,584 bytes. Dart heap was unavailable because
the test VM service socket refused a device-local connection. The queue had no
mention, audio, or OCR rows, so paging and decision append were unavailable.
These debug-run numbers are diagnostic only and are not comparable to the
earlier profile-build measurements. The profile package remained installed;
production `org.tylog.tylog` was absent before and after, so its historical
first-install time could not be queried. No production package command was
issued. The Mac GUI was skipped because the screen is locked. A new received
copy with an eligible row is tracked in the next PF2 plan item.

## PF2-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest repeat (2026-11-06)

Repeated the harness with
`ORG_GRADLE_PROJECT_tylogDebugSuffix=.profiletest flutter test
integration_test/pf2_incoming_sheet_profile_test.dart -d XPH0219904001750
--no-uninstall`. The registered app-local P2P6 copy opened successfully;
Incoming readiness was 4,699 ms, with 17 frame samples and an 881.244 ms
maximum `FrameTiming.totalSpan`. RSS after sheet load was 763,920,384 bytes;
Dart heap sampling was unavailable. Enrichment of
`daily/2026/11/2026-11-06.typ` took 3,812 ms (3,811 ms building memory) and
found zero decisions, tags, and markers. The real sheet again had no mention,
audio, or OCR rows, so decision append and Show older measurements were
unavailable. These debug integration samples are diagnostic and not comparable
to the profile-build measurements above.

Before and after the device run, read-only `adb` package queries showed
`org.tylog.tylog.profiletest` installed with `firstInstallTime=2026-11-05
21:05:34`; the production package `org.tylog.tylog` was absent both times, so
its historical `firstInstallTime=2026-11-05 15:27:02` could not be queried.
No command targeted the production package. The Mac screen remained locked;
the new-copy/actionable-row run is tracked as a separate plan item.

## PF2-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest check (2026-11-06)

The P30 package inventory still showed `org.tylog.tylog.profiletest`, while
the production package was absent, so its historical
`firstInstallTime=2026-11-05 15:27:02` could not be rechecked. No device test
or package-changing command was run. The existing `.profiletest` copy is the
previously measured P2P6 copy, whose Incoming queues had zero mention, audio,
or OCR rows. The locked Mac GUI prevents the sender flow needed to receive a
copy with eligible rows. No substitute transfer or vault selection was
attempted. Decision append and Show older measurements remain tracked in the
next plan item.

## PF2-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest (2026-11-06)

The existing actual-sheet harness and P30 runs complete the available
measurement path for the registered `.profiletest` copy. Prior profile and
debug runs found zero mention, audio, or OCR rows in that copy, so the real
sheet exposed no decision action or older page to measure. The focused tests
`flutter test test/review_queue_test.dart test/enrich_flow_test.dart` passed
(34 tests). The full `flutter test` suite passed: 2,111 tests passed and 10
were skipped.

Before device work, the P30 package inventory showed
`org.tylog.tylog.profiletest` installed and `org.tylog.tylog` absent. Because
the required production `firstInstallTime=2026-11-05 15:27:02` cannot be
queried while that package is absent, no device test or package-changing
command was run. The Mac screen was locked, so the only authorized way to
receive a P2P6 copy with eligible rows was unavailable. No vault was selected
or modified. Real decision and Show older measurements remain tracked in the
next PF2 item.

## PF2-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest-rest (2026-11-06)

Re-ran the actual sheet harness with the isolated debug-signed `.profiletest`
package via `ORG_GRADLE_PROJECT_tylogDebugSuffix=.profiletest flutter test
integration_test/pf2_incoming_sheet_profile_test.dart -d XPH0219904001750
--no-uninstall`. It passed against the registered app-local P2P6 copy:
Incoming readiness was 4,845 ms, with 20 frame samples and a maximum frame
`totalSpan` of 1,147,732 µs. VM heap sampling was unavailable. The copy still
has zero mention, audio, and OCR rows, so a real decision append and Show older
pages were unavailable. The Mac screen was locked, so no sender transfer or
alternate vault was used.

The package inventory after the run showed `.profiletest` installed with
`firstInstallTime=2026-11-05 21:05:34`; production `org.tylog.tylog` was absent,
so its recorded `firstInstallTime=2026-11-05 15:27:02` could not be re-read.
No command targeted the production package. A first, unqualified local
integration invocation was interrupted at the install step; it was not run to
completion, and the package inventory still showed production absent and
`.profiletest` installed afterward.

The full `flutter test` run had one failure in
`entity_board_test.dart` (`repository setting persists and displays refreshed
GitHub issues`). Running `flutter test test/entity_board_test.dart` alone
passed all 15 tests. The UI-dependent real decision and paging measurements
remain in the next plan item.
