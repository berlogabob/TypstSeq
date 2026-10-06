# P21/P23 native runs on the A24 (2026-10-03)

Status: P21 WAIVED by the user on 2026-10-06; search quality is judged by real use instead. P05's 90 relevance labels and Recall@10 scoring are also waived. The native results below remain historical evidence.

A24 (`000251565001005`) profile `.profiletest` build via `scripts/p21_android.sh`, 49-note
fixture vault, pinned model pushed offline, at commit 5f7db8e.

| Run | Index | First query | Warm p50 | Warm p95 |
|---|---:|---:|---:|---:|
| P21 A24 | 2,407 ms | 14 ms | 13 ms | 16 ms |

P21 passes: model install, incremental index, cited searches in the real Search screen,
note-citation navigation, stale-row removal.

P23 passes all six steps with none skipped (filter, cited passage, PDF annotation
save/reassign/reopen, filtered report with bibliography, stale row, source/PDF bytes
unchanged). Report sha256 `c329961e…564ac`, identical to the Mac and P30 runs, so the export
is deterministic across platforms.

One non-fatal log line during P21: `Dart_LookupLibrary: library 'package:tylog/vault_service.dart'
not found`. The headless background-service entry point is looked up in the test build, which
does not include it. The test still passes; this is a test-build artifact, not seen as a failure.

Before the 2026-10-06 user waiver, remaining for P21 closure: the P05 judged quality gate (human labels), and a real-vault run
(blocked on first-index throughput, see proxy-runs.md).
