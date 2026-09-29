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
