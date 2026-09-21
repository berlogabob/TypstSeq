# P09d4 — synthetic resumable import rehearsal

Status: PASS

The opt-in host test creates a deterministic 10,000-note Logseq manifest and
job, recreates the runner for each bounded batch, and forces ten materializer
interruptions. The final job has 10,000 written items, 10,000 nodes, and 10,000
revisions with unique IDs. The deterministic node/content aggregate is
`c0f2e8832e81045e7e8777dc60c95f5a1aa85fc37ad82ccf8a388af39273eee5`.

Run:

```text
TYLOG_RUN_P09D4=1 flutter test \
  test/import/legacy_import_10k_rehearsal_test.dart
P09D4 notes=10000 interruptions=10 total_ms=10903 \
validation_ms=1970 validation_pct=18.1 \
aggregate=c0f2e8832e81045e7e8777dc60c95f5a1aa85fc37ad82ccf8a388af39273eee5
1 test passed
```

Equivalent batch-wide validation queries, measured beside each runner call,
accounted for 18.1% of the rehearsal wall time. This probe duplicates those
queries rather than instrumenting production, so it is a conservative signal,
not an isolated profile. No production optimization is justified by this
single host rehearsal.

## Host rerun (2026-09-21)

The same command passed again with 10,000 notes and 10 interruptions:

```text
P09D4 notes=10000 interruptions=10 total_ms=16606
validation_ms=1768 validation_pct=10.6
aggregate=c0f2e8832e81045e7e8777dc60c95f5a1aa85fc37ad82ccf8a388af39273eee5
1 test passed
```

The aggregate is unchanged, confirming deterministic terminal accounting. The
wall time varies with host load; the validation share decreased to 10.6% on
this run. Private A024 rehearsal remains the only P09 execution gap.
