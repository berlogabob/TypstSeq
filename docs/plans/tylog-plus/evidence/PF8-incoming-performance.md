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
