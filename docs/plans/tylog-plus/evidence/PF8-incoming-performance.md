# PF8 Incoming sheet performance slice (2026-11-05)

The prior P30 profile sample recorded 4,484 ms until Incoming was ready,
32 Flutter frame samples with a 499.338 ms maximum, and a +137,830,528-byte
Dart heap delta. The active profile vault copy had no visible mention, audio,
or OCR rows. The sheet rebuilt enrichment memory for the daily-note page, and
its generic decision snapshot also re-read the same enrichment feedback and
shown ledgers that memory construction had just loaded.

This slice changes the decision snapshot to load only explicit decision logs
for Incoming's audio/OCR queues. The default `loadDecisions` behavior still
merges enrichment feedback and shown ledgers for callers that need them. The
Incoming mention loader now resolves its page candidates before constructing
vault-wide enrichment memory; an empty or ineligible page returns the current
views without building that memory.

Focused checks passed: `test/review_queue_test.dart`,
`test/enrich_flow_test.dart`, and `packages/tylog_core/test/attention_test.dart`.
The new core regression verifies the audio/OCR-only decision read does not list
or parse either enrichment ledger.

The P30 post-change thresholds are not claimed. The installed
`org.tylog.tylog.profiletest` copy is release-signed; Flutter's integration
test launcher builds the debug variant, which cannot safely update that
package's data. `flutter drive` is prohibited by the device rules. Use a
release-signed instrumentation path for the remaining measurement. Production
`org.tylog.tylog` was absent during this run, so its required
`firstInstallTime=2026-11-05 15:27:02` could not be re-read; no production
package command was issued. The Mac GUI was locked and skipped.

## PF8-rest follow-up (2026-11-05)

The PF8 regression checks passed: `flutter test test/review_queue_test.dart`
(8 tests), `flutter test test/enrich_flow_test.dart` (26 tests), and
`dart test test/attention_test.dart` from `packages/tylog_core` (9 tests). The
full `flutter test` suite passed with 2,089 tests and 10 skips.

Built the profile APK with
`./gradlew :app:assembleProfile -PtylogProfileSuffix=.profiletest` using the
installed JDK 25. `apksigner` verified the release certificate and `aapt`
confirmed application ID `org.tylog.tylog.profiletest`. The project exposes
only the debug Android instrumentation runner task; Flutter's supported
`flutter test` device route targets a separate debug package, which does not
have the existing `.profiletest` vault registry. No APK was installed and no
device package was launched or modified. Therefore this run has no post-PF8
ready-time, frame, or heap measurements, and the earlier 4,484 ms / 499.338 ms
/ +137,830,528-byte sample remains a pre-change baseline only.

Production `org.tylog.tylog` was absent both before and after device work, so
the required historical `firstInstallTime=2026-11-05 15:27:02` could not be
verified. The Mac GUI was locked and skipped. No `.typst_flutter_prebuilt`
files were changed. The release-signed, profile-compatible Dart instrumentation
runner and the post-change measurements are tracked in PF8-rest-rest.

## PF8-rest-rest follow-up (2026-11-06)

Added an Android instrumentation entry point that launches the registered
`MainActivity`, plus a read-only Incoming harness that records ready time, max
Flutter frame, and Dart heap delta. Built the profile app with
`./gradlew :app:assembleProfile -Ptarget=integration_test/pf2_incoming_sheet_profile_test.dart -PtylogProfileSuffix=.profiletest`,
assembled the matching Android test APK, and ran it with `adb install -r` and
`am instrument`. The first attempt used the abstract FlutterActivity and never
started Dart tests; changing the rule to MainActivity fixed the runner.

The P30 `.profiletest` real-vault copy contained 10,085 indexed notes and 1,001
daily mention sidecars. Initial profile instrumentation measured 5,120 ms
ready, a 504.134 ms maximum frame, and +142,889,104 bytes heap from before app
startup. Measuring heap around only the Incoming open corrected the scope.
Profiling showed 4,531 ms resolving six daily candidates one at a time, each
starting a separate compute isolate, and 513–955 ms listing all mention
sidecars. Incoming now derives candidate days from the loaded index, resolves a
page in one compute call, and starts independent queue reads together.

Final P30 profile result: ready 1,358 ms; max Flutter frame 336.952 ms; Dart
heap 160,181,296 bytes before and 151,744,784 bytes after (−8,436,512 bytes,
within the 40 MB delta target). The ready target is <1.5 s. The harness made no
review decisions or other vault writes. The production package
`org.tylog.tylog` was absent before and after device work, so its required
`firstInstallTime=2026-11-05 15:27:02` could not be queried; it was not
installed, launched, cleared, or uninstalled. The isolated `.profiletest`
package retained its `firstInstallTime=2026-11-05 21:05:34`. The Mac GUI
remained locked and was skipped.

Focused Incoming/review queue tests passed. The full `flutter test` suite passed
with 2,096 tests and 10 skips. The profile APK build also passed after the
final source changes.
