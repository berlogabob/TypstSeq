# P12 frame gates on the A24 (2026-10-03)

A24 (`000251565001005`) profile build, `-PtylogProfileSuffix=.profiletest`, defines
`P12_FRAME_GATE`, `P12_WINDOW`, `TYLOG_EDITOR_WINDOW` = true, at commit 2d5cd9d.
Refresh measured at 120 Hz (budget 8.33 ms). A frame counts once if build or raster is over budget.

| Gate | Duration | Edits | Over budget | Build p95 | Raster p95 | Span p95 |
|---|---:|---:|---:|---:|---:|---:|
| Formatted, 900 rows | 300 s | 1,104 | 10 (0.91%) | 6.9 ms | 4.8 ms | 13.0 ms |
| Plain, 900 rows | 300 s | 1,200 | 7 (0.58%) | 6.2 ms | 4.9 ms | 12.6 ms |

Both pass <1% with no hang. All over-budget frames are build, none raster. The formatted margin
is thin (0.91%). Total edit latency (span) is reported separately and is not the gate.
Still open for P12: the real-keyboard/IME check by hand on the A24.
