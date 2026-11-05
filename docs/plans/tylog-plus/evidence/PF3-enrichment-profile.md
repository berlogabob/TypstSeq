# PF3 enrichment profile (2026-11-05)

Device: Huawei P30, Android, adb serial `XPH0219904001750`. Ran
`integration_test/pf3_enrichment_profile_test.dart` in a profile build with
`-PtylogProfileSuffix=.profiletest`. The harness only installed and ran as
`org.tylog.tylog.profiletest`; the production package was not targeted. The
Mac screen was locked, so no GUI profiling was attempted. No native harness
build was copied into `.typst_flutter_prebuilt`.

The synthetic fixtures contain 1,000 or 10,000 eligible person pages with
distinct exact titles and a daily note with 1, 20, or 100 matching mentions.
Each case calls production `EnrichMemory.build` and `resolveEnrichDay` through
`compute`, checks that every mention returns a decision, then renders those
decisions in a Flutter list. No feedback, tags, links, markers, vault reads, or
SAF I/O are included. Times are one profile run and diagnostic, not thresholds.

| Pages | Mentions | Memory ms | Resolve ms | Total ms | Root CPU samples (1 ms period) | Dart heap delta | Flutter frame spans |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| 1,000 | 1 | 6 | 56 | 62 | 6 | +974,912 B | 691.445 ms* |
| 1,000 | 20 | 2 | 131 | 133 | 3 | −73,127,888 B | 4.274 ms |
| 1,000 | 100 | 2 | 613 | 615 | 2 | −71,931,504 B | 19.097, 4.523, 7.030 ms |
| 10,000 | 1 | 63 | 355 | 418 | 18 | −65,781,472 B | 10.224, 6.317 ms |
| 10,000 | 20 | 48 | 892 | 940 | 38 | −65,286,128 B | 4.602, 10.683 ms |
| 10,000 | 100 | 39 | 2,622 | 2,661 | 42 | −61,726,992 B | 7.652, 7.274 ms |

The full run's Dart heap rose from 9,015,200 B to 94,261,984 B (+85,246,784 B);
process RSS at the end was 318,918,656 B. Per-case heap deltas are post-operation
snapshots, so negative values indicate collection during the interval and are
not peak allocations. CPU samples are sparse VM sampler observations of the
root isolate while the worker calls ran; multiplying by the 1 ms sampling
period is only a rough sampled-CPU estimate. The 691.445 ms first frame is the
initial harness render and is excluded from any steady-state interpretation.

This is a synthetic algorithm and rendering profile, not a real-vault opening
or a sustained frame-rate study. It does not represent app storage, Incoming,
SAF, or the full seven-day enrichment workflow.
