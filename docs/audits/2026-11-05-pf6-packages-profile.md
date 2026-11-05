# PF6 vendored package profile — 2026-11-05

Measured on the Huawei P30 (`XPH0219904001750`), Android profile build, installed
as `org.tylog.tylog.profiletest`. The production `org.tylog.tylog` package was
left installed and untouched. Each case used a fresh app-local temporary vault;
vault initialization and fixture creation were outside the readiness timer.
The 0/100/1,000 files were three-byte files at
`_system/packages/pkg-N/1.0.0/lib.typ`.

| Package files | Ready (ms) | Ready notifications | Storage list/read/exists calls | Flutter frames (P95 / P99 / max, µs) | CPU samples (1 ms period) | Dart heap before → after (bytes) | Process RSS before → after (bytes) |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 0 | 73 | 3 | 14 / 25 / 44 | 2 (5,950 / 5,950 / 5,950) | 19 | 25,633,136 → 26,699,632 | 202,686,464 → 328,945,664 |
| 100 | 475 | 1 | 214 / 125 / 44 | 15 (7,381 / 9,274 / 9,274) | 142 | 27,946,832 → 9,937,088 | 252,506,112 → 345,374,720 |
| 1,000 | 3,733 | 1 | 2,014 / 1,025 / 44 | 113 (6,619 / 7,358 / 7,947) | 1,166 | 29,779,328 → 19,738,800 | 264,085,504 → 349,208,576 |

The same three cases each ran a separate forced rebuild after package loading
with 205 tiny note files. Each emitted three `syncProgressTick` updates and zero
general workspace notifications for progress, matching the narrow notifier
contract. Package loading used app-local `File` storage, so it made zero Android
platform-channel calls; the list/read/exists counts above are Dart storage API
calls, not SAF bridge operations.

Flutter frame timings came from `SchedulerBinding`; CPU samples and Dart heap
came from the profile VM service; process RSS came from `ProcessInfo.currentRss`.
RSS includes Dart and native resident pages and cannot isolate native heap.
The small frame counts, especially at 0 files, make percentiles descriptive
only. This fixture does not measure SAF channel/provider latency, Mac GUI
profilers were unavailable because the screen was locked, and the synthetic
packages are not evidence for third-party package sizes or contents.
