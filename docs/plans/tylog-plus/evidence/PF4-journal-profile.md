# PF4 journal profile (2026-11-05)

Device: Huawei P30 (`ELE-L29`), driven only through adb serial
`XPH0219904001750`. Flutter profile build used
`-PtylogProfileSuffix=.profiletest` and ran as
`org.tylog.tylog.profiletest`; the production `org.tylog.tylog` package was
not installed over. The Mac screen was locked, so Mac GUI checks were skipped.
No `svc power stayon` command was used and no native harness artifact was
copied into `.typst_flutter_prebuilt`.

Command:

```sh
flutter drive --no-pub --no-dds --profile \
  -PtylogProfileSuffix=.profiletest \
  --device-id XPH0219904001750 \
  --driver=test_driver/integration_test.dart \
  --target=integration_test/pf4_journal_profile_test.dart
```

The harness ran full-history traversals at 50, 500, and 5,000 daily notes with
both in-memory content and files in a test-specific on-device temporary
directory through `LocalVaultStorage`. Each run verified that every unique day
path was read and that all 20 task rows on the newest day rendered. Browsing
used repeated upward flings until all days had loaded. It forced GC immediately
before both the start and end Dart heap readings. CPU samples are from the root
isolate at a 1,000 us sampling period; frame percentiles use Flutter
`FrameTiming.totalSpan`; RSS includes Flutter and native process allocations.

| Content | Days read / indexed | Fling gestures | Browse time | CPU samples | Frame P50 / P95 / P99 | Max frame | Dart heap after GC, before → after (delta) | Process RSS |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Memory | 50 / 50 | 8 | 5.505 s | 1,837 | 11.12 / 26.52 / 47.34 ms | 63.82 ms | 30.47 → 28.61 MB (-1.86 MB) | 435.86 MB |
| Memory | 500 / 500 | 73 | 44.692 s | 15,236 | 12.31 / 30.07 / 41.13 ms | 72.23 ms | 28.97 → 29.30 MB (+0.32 MB) | 562.85 MB |
| Memory | 5,000 / 5,000 | 716 | 441.480 s | 31,975 | 12.86 / 31.49 / 40.40 ms | 71.66 ms | 37.29 → 32.39 MB (-4.90 MB) | 550.49 MB |
| Disk | 50 / 50 | 8 | 5.480 s | 1,979 | 11.53 / 32.47 / 50.47 ms | 72.43 ms | 34.23 → 32.49 MB (-1.75 MB) | 559.39 MB |
| Disk | 500 / 500 | 72 | 45.253 s | 16,534 | 12.94 / 31.82 / 40.59 ms | 71.14 ms | 31.03 → 30.77 MB (-0.26 MB) | 492.02 MB |
| Disk | 5,000 / 5,000 | 721 | 444.241 s | 32,237 | 12.95 / 31.20 / 40.69 ms | 75.89 ms | 36.75 → 36.56 MB (-0.20 MB) | 558.48 MB |

These are single-run profile measurements. Heap deltas vary in sign, so they do
not establish a retained-heap growth trend; the snapshots are controlled by
forcing GC at both endpoints, and all raw readings are retained above. RSS is
not a Dart heap measure. The disk fixture uses app-local files, not SAF; SAF
provider latency was not measured. Flutter frame totals include profile-harness
work and scrolling, not platform decor timings.
