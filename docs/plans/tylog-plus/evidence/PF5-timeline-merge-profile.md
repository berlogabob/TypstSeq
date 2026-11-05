# PF5 timeline and merge preview profile (2026-11-05)

Device: Huawei P30 (`ELE-L29`), adb serial `XPH0219904001750`. The profile
APK used `-PtylogProfileSuffix=.profiletest` and ran as
`org.tylog.tylog.profiletest`; the production package was not installed over.
The SAF fixture was the dedicated `Downloads/PF5-profile-fixture` tree. The
harness removed generated notes and left that folder empty. No `svc power
stayon` command was used, and no native harness build was copied into
`.typst_flutter_prebuilt`. The Mac screen was locked, so GUI checks were
skipped.

Command:

```sh
flutter drive --no-pub --no-dds --profile \
  -PtylogProfileSuffix=.profiletest \
  --device-id XPH0219904001750 \
  --driver=test_driver/integration_test.dart \
  --target=integration_test/pf5_timeline_merge_profile_test.dart
```

Fixtures contained 50, 500, or 1,000 generated notes for app-local storage,
and 50 or 500 generated notes for SAF. Each merge preview visited all fixture
notes and was accepted; two preview files were produced. Timeline rendering
used one entity linked to each fixture note. These are synthetic app-local and
SAF fixtures, not measurements from a user's real vault.

| Backend | Notes | Timeline build | Flutter frames (n, p50 / max) | Timeline root-isolate CPU samples |
| --- | ---: | ---: | ---: | ---: |
| App-local | 50 | 136 ms | 2, 35.11 / 35.11 ms | 30 |
| App-local | 500 | 124 ms | 2, 13.53 / 13.53 ms | 18 |
| App-local | 1,000 | 128 ms | 2, 13.96 / 13.96 ms | 19 |
| SAF | 50 | 120 ms | 2, 22.39 / 22.39 ms | 16 |
| SAF | 500 | 126 ms | 2, 13.94 / 13.94 ms | 10 |

| Backend | Notes | Reads | UTF-8 bytes read | Sum of read latency | Preview elapsed | Root-isolate CPU samples | Dart heap after GC, before → after (delta) |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| App-local | 50 | 52 | 11,086 | 71 ms | 21 ms | 9 | 25.2 → 107.9 MiB (+82.7 MiB) |
| App-local | 500 | 502 | 108,186 | 778 ms | 224 ms | 88 | 26.9 → 107.4 MiB (+80.5 MiB) |
| App-local | 1,000 | 1,002 | 216,186 | 1,502 ms | 442 ms | 191 | 27.9 → 107.6 MiB (+79.7 MiB) |
| SAF | 50 | 52 | 11,086 | 136 ms | 50 ms | 12 | 21.3 → 106.3 MiB (+85.1 MiB) |
| SAF | 500 | 502 | 108,186 | 1,630 ms | 580 ms | 179 | 25.5 → 111.3 MiB (+85.8 MiB) |

Limitations: the VM CPU sampler observes only the root isolate at a 1,000 us
sampling period; sample counts are not CPU-time totals. Frame results contain
two `FrameTiming.totalSpan` samples per timeline build, so these runs establish
observed frame costs but not stable percentiles. Read latency is summed across
each `readText` operation and can exceed elapsed wall time when SAF reads
overlap. Merge heap endpoints use forced GC before measurement; heap values
include Flutter integration-test and fixture state. The harness measures
profile-build behavior and does not establish release performance.
