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

## Scope limit

This reproducible vertical slice measures the production audio and OCR
loaders and renders their queue rows. It does not open the complete Incoming
bottom sheet, include enrichment mention computation, or use a SAF-backed
fixture. A real sheet readiness/row-frame/mention run and SAF-backed decision
and sidecar measurements remain in PF2-rest-rest-rest-rest-rest. A real SAF
grant could not be established because the Mac screen was locked. The P30 run
does not imply observations about an external vault or provider.
