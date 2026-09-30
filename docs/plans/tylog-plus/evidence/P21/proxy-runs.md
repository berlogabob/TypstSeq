# P21/P23 native runs (2026-09-29)

Generated 49-note fixture vault (copy only), pinned model pushed or copied offline.
Mac = macOS debug build. P30 = Huawei P30 profile `.profiletest` build via
`scripts/p21_android.sh`. The P30 is a proxy and does not close the A24 gate.

| Run | Index | First query | Warm p50 | Warm p95 |
|---|---:|---:|---:|---:|
| P21 Mac | 1,070 ms | 19 ms | 4.9 ms | 5.9 ms |
| P21 P30 | 5,696 ms | 45 ms | 39 ms | 54 ms |

The P21 run covers model install, incremental index, three cited searches in the real Search
screen, note-citation navigation, and stale-row removal. Found and fixed: note citations
had `onTap: null` (272afb0).

The P23 run covers all six steps (filter, cited passage, PDF annotation save/reassign/reopen,
deterministic filtered report with bibliography, stale row, source/PDF bytes unchanged), and
passes on Mac and P30. Report sha256 `c329961e…564ac`. Found and fixed: opening a
deleted note threw FileSystemException (aa76d0f).

Remaining: P21/P23 on the real vault (Mac profile build, then A24), and P05 quality
through this path.

## Real-vault indexing throughput (2026-09-30)

The real Mac vault copy splits into 101,523 chunks. The P21 test measured 3.5 chunks/s
(a projected 8 h), but that run had two controllers indexing the same database: the app's
own (`lib/app_mobile.dart` ~465) and the test's direct one. Both serialize on the Rust
global model lock. The ORT-only bench (`tool/p05_ort_bench`, 200 passages, pinned O4
model) gives 27 ms/chunk (37/s, ~46 min for the vault). Level3, perf-core intra threads,
and batch 16 each change it by ≤3%, so none was kept. The pinned O4 file holds fp16
weights; fp32 variants measure ~39/s, and the pinned model is unchanged. Dart-side
costs are small: `pendingChunks` 0.4–1.6 ms per batch, chunk write 0.2–7 ms. A
status index (schema 9) gave no measurable gain and was not kept.

Open: measure a single-controller in-app run (the test must drive the app's
controller only) on Mac and phone. Expect about 46 min on the Mac; phones are slower.

### Single-controller rerun (2026-09-30)

With only one controller indexing, the real vault runs at 5.97 chunks/s (3,582 chunks
in 10 min), projecting ~4 h 43 min for 101,523 chunks on the Mac. That is still ~6x
slower than the ORT-only bench (27 ms/chunk). Unexplained. Suspects: real chunks
running longer in tokens than the bench passages, and the app's ORT build differing
from the bench's `download-binaries`. Open perf item: a first full index is hours on
Mac and longer on phones. Search itself stays fast (fixture p50/p95 3.9/4.5 ms).
