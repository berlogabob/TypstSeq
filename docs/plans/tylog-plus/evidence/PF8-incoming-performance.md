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
