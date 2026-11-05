# PF2 Incoming queue profile (2026-11-05)

Device: Huawei P30, Android, adb serial `XPH0219904001750`. Ran the profile
integration harness with package suffix `.profiletest`; the production package
and vault were not targeted. The Mac screen was locked, so no GUI profiling was
attempted.

The harness exercised the production `ActionableSidecarSummary` audio loader
against 1,000 one-row JSON sidecars in app-private temporary storage. Sparse
had 10 actionable rows and 990 rejected rows in a device decision ledger;
dense had 1,000 actionable rows. It loaded decisions, loaded the first page,
requested Show older at offset 20, appended an accepted decision, refreshed
from the in-memory decision snapshot, rendered the visible page, and captured
Flutter `FrameTiming` spans. Counts below are one run and should be treated as
diagnostic samples, not gates.

| Fixture | Decision load | First page | Show older | Decision refresh | Rows: first / older / after decision | Dart heap delta | Process RSS delta |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Sparse | 6 ms; 3 lists, 1 byte read, 94,950 bytes | 1,543 ms; 1 list, 1,000 sidecar reads, 79,670 bytes | 318 ms; 1 list, 0 reads | 523 ms; 1 list, 0 reads | 10 / 0 / 9 | +1,491,648 bytes | +19,705,856 bytes |
| Dense | 1 ms; 3 lists, 0 byte reads | 1,800 ms; 1 list, 1,000 sidecar reads, 79,670 bytes | 374 ms; 1 list, 0 reads | 484 ms; 1 list, 0 reads | 20 / 20 / 20 | +994,496 bytes | +28,925,952 bytes |

Decision append issued one directory-create and one `appendBytes` call. The
cached Show older and post-decision refresh made no sidecar reads. The latter
still lists the sidecar directory and filters the cached rows.

After rendering both pages, the four Flutter frame total spans were 28.876,
51.523, 8.261, and 22.746 ms. These are four sampled `FrameTiming.totalSpan`
values, not separate build/raster values or a sustained frame-rate gate. Heap
was queried from the VM service; deltas are against the harness baseline. RSS
is process-wide and includes native memory. Cold app startup and fixture
construction are outside the timed queue intervals.

## Scope limit

This is a reproducible profile slice of the production audio loader and its
cache, not the complete Incoming sheet. The test uses app-private local storage,
does not exercise mention or OCR loaders, and renders a representative list
rather than opening the app's bottom sheet. Full sheet readiness, row frames,
mention/OCR work, and SAF-backed storage remain in PF2-rest-rest-rest-rest.
