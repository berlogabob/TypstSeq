# P12 frame gates on the Huawei P30 (proxy, 2026-09-29)

Proxy only: the P30 (ELE-L29, 60 Hz) does not close the A24 gate. Profile build
with `-PtylogProfileSuffix=.profiletest`, idle phone, defines `P12_FRAME_GATE`,
`P12_WINDOW`, `TYLOG_EDITOR_WINDOW` = true, at commit 272afb0.

| Gate | Edits | Frames over 16.7 ms | Build p95 | Raster p95 |
|---|---:|---:|---:|---:|
| Plain, 900 rows | 1,200 | 6 (0.5%) | 7.0 ms | 11.1 ms |
| Formatted, 900 rows | 1,064 | 1 (0.09%) | 9.5 ms | 12.8 ms |

Both pass <1% on the slower phone, so the 400-char window holds on the formatted
workload when the phone is idle. The A24 formatted rerun and the real-keyboard/IME
check remain.
