# PF4 journal profile (2026-11-05)

Device: Huawei P30 (`ELE-L29`), driven only through adb serial
`XPH0219904001750`. Flutter profile build used
`-PtylogProfileSuffix=.profiletest` and ran as
`org.tylog.tylog.profiletest`; the production `org.tylog.tylog` package stayed
installed. The Mac screen was locked, so no Mac GUI checks were attempted.
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

Each run built an in-memory daily index of 50, 500, or 5,000 notes and rendered
20 task rows from the newest day. Forty upward fling gestures exercised journal
scrolling and source-cache trimming. Other entries used a short repeated text
body. The fixture uses an in-memory `VaultStorage` override: it measures index,
widget, and cache behavior without disk or SAF latency. Dart heap snapshots
forced GC before and after the sample. Frame percentiles use Flutter
`FrameTiming.totalSpan`; CPU data is root-isolate VM samples at a 1,000 us
sampling period.

| Days in index | Task rows | 40-fling time | Root CPU samples | Frame P50 / P95 / P99 | Max frame | Dart heap after GC, before → after | Process RSS |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 50 | 20 | 40.969 s | 6,182 | 10.51 / 14.54 / 29.16 ms | 82.07 ms | 30.42 → 30.43 MB (+0.01 MB) | 424.85 MB |
| 500 | 20 | 40.892 s | 6,321 | 10.84 / 15.19 / 25.07 ms | 75.43 ms | 24.90 → 29.72 MB (+4.82 MB) | 432.56 MB |
| 5,000 | 20 | 40.803 s | 6,181 | 10.91 / 14.40 / 18.44 ms | 79.14 ms | 28.94 → 34.77 MB (+5.82 MB) | 432.48 MB |

This is a smoke profile, not a controlled heap study: each size was run once,
the fixture is in memory, the 40 gestures do not traverse every day in the 500-
and 5,000-day indexes, and RSS includes the Flutter process and native
allocations. Flutter frame totals include fixture rendering and scrolling;
they are not platform decor timings. Repeatable full-history traversal, disk or
SAF-backed content, and heap snapshots after browsing the entire index remain
open under PF4-rest-rest-rest-rest.
