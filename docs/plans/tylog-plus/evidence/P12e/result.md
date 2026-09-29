# P12e result — latency acceptance

Status: STARTUP/OPEN/SAVE PASS / EDITOR ACCEPTANCE OPEN

Current interpretation: the historical `totalSpan`-based "dropped equivalents"
are frame-latency estimates, not measured dropped frames. They do not establish
the stage-budget gate. See the [measurement correction](#stage-budget-measurement-correction-2026-09-23)
below; earlier measurements are preserved as history.

Host acceptance uses the plan gates from `docs/plans/tylog-plus/plan.typ` and runs 30 database startups plus 100 durable saves of 50 KB notes:

```bash
flutter test test/database/p12_latency_acceptance_test.dart
```

Observed on the development Mac:

- Startup: p50 1 ms, p95 2 ms, max 370 ms across 30 samples.
- Durable open/save: p50 2 ms, p95 2 ms, max 32 ms across 100 samples.
- Gates: startup p95 <= 2,000 ms; save p95 <= 150 ms — PASS.

Full regression suite: `flutter test` — 686 passed, 2 skipped.

Android release/profile samples remain device-gated. The required follow-up is `flutter build apk --profile`, install over the release app, then capture 30 startup and 100 open/save samples on the A24.

### A24 database smoke (debug integration runner)

The same 30-startup/100-save workload also ran on the connected A24 through
`integration_test/p12_latency_native_test.dart`:

```text
startup_ms p50=2 p95=6 max=53; save_ms p50=6 p95=9 max=75; samples=30/100
```

Both thresholds passed. This is useful device evidence for the SQLite workload,
but it is not the release/profile gate: `flutter test` installs a temporary
debug test APK. P12e remains device-pending until the workload is exercised
inside a profile build with the app's normal startup path.

### A24 production cold-start timing

The installed production package (`org.tylog.tylog`, version `0.4.4`, profile
APK installed over the existing app) was force-stopped and launched 30 times
with Android activity timing. The vault was not cleared or modified.

```text
TotalTime_ms p50=417 p95=450 max=452 samples=30
```

This passes the 2,000 ms startup gate. The remaining device measurement is a
profile-run normal editor save/open workload; the 100-save result above is the
bounded database workload from the debug integration runner.

### A24 workspace save path

The real `WorkspaceController.save()` route was exercised on a temporary local
vault with the durable database attached. Across 100 50 KB editor saves:

```text
editor_save_ms p50=11 p95=15 max=179 samples=100
```

The p95 save gate (150 ms) passed; one outlier reached 179 ms. This is still a
debug integration runner, so the profile-build repetition remains required.

### A24 profile save-path acceptance

The same test ran through `flutter drive --profile` with the release-shaped
profile APK and the integration driver:

```text
editor_save_ms p50=2 p95=3 max=16 samples=100
```

The profile save gate passed. Combined with the 30 production-package cold
starts above (p95 450 ms), the startup and save timing gates are satisfied.
The scripted five-minute frame-budget gate and normal note-open timing still
need a dedicated profile workload.

The same profile run exercised the normal workspace note-read/adoption path
100 times for the 50 KB note:

```text
editor_save_ms p50=3 p95=4 max=23; editor_open_ms p50=0 p95=0 max=1; samples=100/100
```

The startup, open and save timing gates now pass on A24. Only the scripted
five-minute frame-budget workload remains for P12e.

### Frame-gate blocker found on A24

An exploratory profile run mounted the real `TyLogRichEditor` with a 36 KB
note and appended text every 250 ms. Android reported **267 skipped frames**
and the profile app became unresponsive before the five-minute window ended.
The run was stopped and its private log remains outside the repository. This
is evidence that the frame gate is not yet satisfied for long active notes;
the next performance task is to reduce editor rebuild/layout cost before
repeating the five-minute acceptance workload.

After removing the full reparse for plain notes, a 30-second profile probe with
the same 36 KB editor and 250 ms edits stayed responsive but still recorded
998 late frames out of 1,840 (worst gap 37 ms). The change removes the hang and
cuts the worst single stall, but the frame ratio remains far above the 1%
acceptance gate. A virtualized or block-level editor is still required for
large active notes.

### Lazy undo snapshot remediation (2026-09-21)

`TyLogEditingController` no longer copies the full document before every
keystroke. Plain edits take the undo snapshot immediately before the first
model mutation, while protected edits and recovery paths retain the same
snapshot semantics. `flutter test --no-pub test/rich_editor_test.dart
test/controlled_editor_test.dart` — 101 tests passed; targeted analyzer clean.
This removes avoidable per-keystroke work, but the A24 five-minute frame run is
still required before the 1% gate can close.

### A24 rerun after lazy snapshots (2026-09-21)

Command: `flutter drive --profile --driver=test_driver/integration_test.dart
--target=integration_test/p12_editor_frame_native_test.dart
-d 000251565001005`.

The five-minute workload completed and stayed responsive: 17,343 frame ticks,
1,199 edits, 1,357 dropped-frame equivalents (~7.8%), and a 32 ms worst gap.
The 1% gate therefore remains blocked. The controller optimization removed
avoidable model-copy work but did not solve the full-document `TextField`
layout cost; the next remediation must reduce or virtualize that layout.

### Finite viewport experiment (2026-09-21)

The editor was temporarily changed to a finite 40-line viewport with internal
scrolling, then rerun on the same A24 profile workload. It completed with
17,300 frame ticks, 1,199 edits, and **1,390 dropped-frame equivalents
(~8.0%)**, with a 32 ms worst gap. This did not improve the gate and was
reverted. A block-level or virtualized editor remains required; P12e stays
FRAME BLOCKED.

### A24 span fast-path experiment (2026-09-21)

The editor was temporarily changed to emit one `TextSpan` for plain paragraph
notes, avoiding per-block span construction. The same profile workload still
completed at **17,223 frame ticks, 1,199 edits, and 1,468 dropped-frame
equivalents (~8.5%)**, with a 32 ms worst gap. The change was reverted because
the result was worse; the dominant cost is full-document `RenderEditable`
layout, so P12e remains FRAME BLOCKED.

### Virtualized-editor prototype (2026-09-21)

A prototype `ListView.builder` editor for long plain notes was exercised on the
A24 profile workload, together with an incremental last-block append path. It
completed at **17,214 frame ticks, 1,199 edits, and 1,467 dropped-frame
equivalents (~8.5%)**, with a 48 ms worst gap. The prototype was reverted: it
did not improve the gate and did not yet preserve full editor parity. The next
attempt must isolate and reduce the model/source-update cost before another UI
replacement.

### Host model update benchmark (2026-09-21)

The 1,200-append host benchmark (`test/p12_editor_model_benchmark_test.dart`)
reported p50 **2.76 ms**, p95 **9.54 ms**, and max **13.14 ms** per append.
The model/source-update path stays below the 50 ms per-edit ceiling; the A24
frame loss is therefore dominated by Flutter rendering/layout work.

### A24 FrameTiming trace (2026-09-21)

The 30-second profile trace (`integration_test/p12_editor_render_trace_native_test.dart`)
completed 119 edits without errors. Flutter delivered one `FrameTiming` sample:
build **4.31 ms**, raster **3.95 ms**. Because the profile driver exposed only
one timing sample, the existing timer-jitter dropped-frame counter cannot be
used as a definitive Flutter frame gate. P12h must switch to a reliable
FrameTiming/DevTools capture before accepting or rejecting an editor rewrite.

### A24 gfxinfo cross-check (2026-09-21)

Android `dumpsys gfxinfo org.tylog.tylog` sampled during the live 30-second
driver run reported only one rendered frame (1 janky, 1550 ms). The Flutter
driver workload is therefore not producing a usable graphics counter stream;
the timer-jitter and post-run gfxinfo results cannot establish a real frame
rate. P12j remains open and requires an interactive app-session capture.

### Clean profile app-session check (2026-09-21)

The profile APK was reinstalled after the integration runner exited and
`org.tylog.tylog/.MainActivity` was launched directly. A screenshot confirmed
the real editor was foreground with the long note. Android `dumpsys gfxinfo`
still reported zero rendered frames during input, so this Impeller/Vulkan
session is not measurable through gfxinfo. The remaining measurement path is a
Flutter VM timeline from a normal profile launch.

### Normal profile VM timeline (2026-09-21)

`flutter run --profile -d 000251565001005 --machine` exposed the VM service at
port 62232. A five-second timeline sample from the foreground profile app
contained 25 real frames: full-frame p50 **0.49 ms**, p95 **3.37 ms**, max
**10.02 ms**; layout p95 **0.365 ms**, max **8.58 ms**; paint p95 **0.598 ms**.
This is a valid baseline, but edits were not injected into the focused field,
so P12j still needs an interactive edit capture with at least 1,000 frames.

### A24 profile frame attribution probe

`flutter drive --profile` ran the existing worker attribution workload (2,000
synthetic notes) for 12 seconds. Worst observed timer gaps were 26 ms while
the index was published, 18 ms while communities were built, 25 ms while the
search projection completed, and 16 ms during search. The test passed and
confirms the worker path is bounded, but this is not the required five-minute
real-editor workload or a frame-budget acceptance result.

### Interactive normal-app edit capture (2026-09-21)

The normal profile app was launched with `flutter run --profile --machine`,
the existing long indexed note was opened in edit mode, and the field was
focused through the real Android input connection. A VM timeline capture during
120 rapid character inserts produced 259 paired `Frame` events with p50
**2.37 ms**, p95 **37.71 ms**, max **46.38 ms**, and **120/259** frames over
the 16.7 ms budget. A second human-paced run (30 inserts at 100 ms intervals)
produced 68 paired frames with p50 **1.44 ms**, p95 **39.88 ms**, max
**43.39 ms**, and **31/68** frames over budget. This is the first valid
interactive evidence that long-note typing still causes frame stalls; P12e and
P12j remain blocked until the capture is repeated for at least 1,000 frames and
the long-note path is reduced or gated.

### Plain-editor qualification attempt (2026-09-21)

The pushed profile build was installed on A24. A plain note was grown from
10.5 KB using Android input, but `adb shell input text` truncated large
payloads and chunked injection stalled the rich editor before the 32 KB gate
could be reached (14.5 KB was accepted after the bounded attempt). No frame
acceptance claim is made from this run; a deterministic fixture or direct vault
file seed is required to exercise the new plain-editor branch on-device.

### Plain-editor SAF fixture capture (2026-09-21)

A disposable 46 KB / 220-block plain note was seeded into the authorized A24
`TyLog` SAF folder and loaded by the normal profile app. The size/blocks gate
selected the stock editor path. Thirty human-paced inserts produced 114 paired
VM-timeline frames with p50 **3.32 ms**, p95 **39.01 ms**, max **59.88 ms**,
and **33/114** frames over 16.7 ms. The gate is functionally verified but does
not meet P12h's frame target; full-document `RenderEditable` layout remains the
dominant cost and P12g's visible-block editor is required.

### P12g visible-block prototype (2026-09-21)

`VirtualPlainEditor` now uses one controller per paragraph with
`ListView.builder`, so only viewport rows create `TextField` render objects.
The host widget test verifies a 220-paragraph note builds fewer than 220
fields, edits the first row, and restores the source through undo. The full
widget suite passes (53 tests). A24 typing, Enter/Backspace, selection, and
five-minute frame acceptance remain open before this prototype can replace the
current gate.

### P12g A24 interaction and frame capture (2026-09-21)

The visible-block editor was exercised on the same 46 KB / 220-block SAF
fixture. Android UI inspection showed one visible `EditText` plus enabled Undo
after typing; Enter and Backspace completed without an input or save error. A
30-character human-paced VM-timeline run produced 120 paired frames with p50
**2.72 ms**, p95 **37.83 ms**, max **57.76 ms**, and **32** frames over
16.7 ms. The debounce improved the p95 versus the first prototype capture, but
the frame gate still fails; source assembly and autosave remain the next
optimization target.

### P12g toolbar-isolation capture (2026-09-21)

After splitting normalized sources on every newline and moving Undo/Redo state
to a notifier, the same A24 fixture produced 121 paired frames during 30
human-paced inserts: p50 **2.81 ms**, p95 **30.52 ms**, max **46.42 ms**, and
**35** frames over 16.7 ms. This improves p95 over the prior 32.52 ms capture,
but the frame budget still fails; remaining stalls need deeper allocation and
raster profiling before P12h can close.

### P12j reliable frame gate harness (2026-09-21)

The five-minute integration workload now collects Flutter `FrameTiming` samples
through `SchedulerBinding.addTimingsCallback` instead of wall-clock timer
jitter. It reports total-span worst case, counts dropped-frame equivalents at a
16.667 ms budget, requires at least 1,000 samples, and fails when dropped
equivalents exceed 1% of samples. The host analyzer is clean; A24 execution is
still required to produce the acceptance result.

### P12h host editor parity (2026-09-21)

The virtual editor now coalesces rapid edits into one undo snapshot and defers
old controller disposal until the next frame, preventing a focused `TextField`
from referencing a disposed controller during Undo. The virtual-editor suite
and full widget suite pass (2 and 53 tests respectively). Only the A24
five-minute frame-budget result remains for P12h.

### P12j A24 profile frame gate (2026-09-22)

The harness uses a live 16 ms pump stream; the corrected profile run produced
`frames=7963 edits=1200 dropped=5573 over_budget=1200 worst_ms=109.18`.
The full rich editor remains the active P12 blocker.

### Actual long-note route (2026-09-22)

The selected `VirtualPlainEditor` path was measured separately with a 30-second
A24 profile workload (900 single-line paragraphs, 120 edits): `frames=1007`,
`dropped=38`, and `worst_ms=20.54`. That is 3.8% dropped-frame equivalents,
so the production long-note route also fails the 1% gate. A `cacheExtent: 0`
probe was worse and was reverted.

Phase attribution on the same harness recorded a no-edit baseline of 989 frames,
zero dropped equivalents, and 12.90 ms worst frame. With edits, the run reached
1,006 frames, 21 dropped equivalents, 26.33 ms worst frame, 11.93 ms worst Dart
build, and 10.53 ms worst raster. A toolbar rebuild debounce probe worsened the
run and was reverted; the remaining cost is in the editable row/render path.

The harness now drives a live 16 ms pump stream; a plain five-minute delay
produced too few timing samples on Android. The corrected profile run produced
`frames=7963 edits=1200 dropped=5573 over_budget=1200 worst_ms=109.18`.
The <=1% dropped-frame gate therefore fails. Startup/save/open timing passes,
but the full rich editor remains the active P12 blocker.

### Repaint-boundary probe (2026-09-22)

Wrapping each visible line in a `RepaintBoundary` was measured on the same A24
profile workload. It produced `frames=969 edits=120 dropped=37
worst_ms=21.44 build_ms=12.05 raster_ms=10.28`, worse than the prior
production baseline of 21 dropped equivalents. The change was reverted; the
remaining bottleneck is shared editable-row layout/render work.

### Isolated A24 profile rerun (2026-09-23)

Profile integration builds used the opt-in `.profiletest` application ID so
they could run beside the installed production app without replacing it. The
actual long-note test's no-edit control now correctly expects zero edits; it
passed with `frames=964 edits=0 dropped=0 worst_ms=14.83`. This fixes a false
test failure in the control path, not the editor.

The 30-second `VirtualPlainEditor` edit run failed the 1% gate:
`frames=1029 edits=120 dropped=26 worst_ms=20.46 build_ms=12.25
raster_ms=9.14` (2.5%). The five-minute rich-editor profile run also failed:
`frames=8101 edits=1200 dropped=4849 over_budget=1199 worst_ms=175.95`
(59.9% dropped-frame equivalents). Idle work is not the cause; active editable
layout/render remains the blocker. No speculative editor code change was made.
Next: capture a DevTools profile trace and use its build/layout/raster
attribution to scope a block-level editor prototype; rerun both profile gates
before accepting a change. Production package and vault were not targeted by
these profile runs.

### Long plain-note route and controller-backed smoke (2026-09-23)

The app previously kept long notes with generated Typst `#show` headers in the
rich editor because its mode gate required an empty source prefix. Long plain
notes now select `VirtualPlainEditor` based on the parsed visible document,
while changes flow through `TyLogEditingController` so the generated header is
retained in serialized source. Protected/rich blocks remain on the rich path.
The virtual editor now waits 300 ms after the last edit before syncing its
whole visible source to the model; this coalesces continuous typing, and pending
text still flushes on pause or dispose.

Host analysis and the focused editor tests pass. An A24 profile smoke using the
`.profiletest` package ID drove 80 controller edits over 20 seconds through the
mounted row callback and confirmed source/header round-trip:
`frames=738 edits=80 dropped=2 worst_ms=16.876 build_ms=8.384
raster_ms=8.794` (0.27% dropped-frame equivalents). This is a smoke result, not
the five-minute acceptance gate.

The subsequent five-minute run was interrupted when A24 moved to Android's
Wi-Fi QR configurator and left the test app in the background. No result from
that run is valid. P12 remains open until an uninterrupted foreground A24 run
produces at least 1,000 timing samples and 1,100 edits with at most 1% dropped
equivalents. Rich-formatted long-note editing also remains unverified after the
route change; the earlier direct rich-editor capture failed badly and must be
retested separately before P12 closes. All runs used synthetic content and the
`.profiletest` package; the production app and vault were not targeted.

### Corrected A24 active-row gate (2026-09-23)

The old short-run frame harness explicitly pumped a frame every 250 ms. An idle
control produced nearly the same dropped-frame count as the edit run, so those
results are harness-generated and are not acceptance evidence. A `benchmarkLive`
experiment also forced redraws at every VSync and was discarded. The gate now
drives the mounted virtual-editor row callback and records one rendered frame
per 4 Hz edit, using the plan's 60 FPS / 16.667 ms target regardless of the
phone's variable 90/120 Hz display mode.

The corrected five-minute A24 profile run on the 900-row plain-note route
recorded `frames=1105 edits=1103 dropped=236`, with p95 total span **18.42 ms**,
worst **22.33 ms**, max build **13.62 ms**, and max raster **9.77 ms**. This
fails the <=1% gate at **21.4%**. Capping each row to six visible lines was
tested, but the five-minute result worsened to 332 dropped equivalents in 1,098
frames; that edit was reverted. The remaining measurable issue is the growing
active paragraph's render/layout cost during typing. Keep P12 open until that
path is optimized and passes the same five-minute gate; rich-formatted long-note
editing still needs its own acceptance run.

### P12k implementation target

Keep the document and Typst source unchanged. Replace the growing paragraph's
single unbounded render object with a bounded active editing window over the
same text, mapped by UTF-16 offsets. Nearby windows should be available for
selection and caret movement; crossing a window edge must preserve typing,
Backspace/Delete, Enter, paste, IME composition, and undo/redo. Do not insert
synthetic separators into serialized content. Compare 256-, 512-, 1,024-, and
2,048-character active paragraphs on A24 to find the layout-cost knee. P12k
passes only when the existing five-minute 900-row profile gate reaches p95
<=16.67 ms and <1% dropped equivalents, source/header round-trip remains exact,
and editing-boundary tests pass. Then run the separate rich-formatted-note gate.

### Active paragraph size sweep (2026-09-23)

The frame harness now accepts `P12_ACTIVE_PARAGRAPH_CHARS` so the active row can
be varied without changing the 900-row document. Four 20-second A24 profile
smokes, each with about 74 edits, show the active-row cost rising with text size
(all use the plan's 16.667 ms budget; these short runs are diagnostic only):

| Initial active paragraph | Frames / edits | Dropped equivalents | p95 span |
| ---: | ---: | ---: | ---: |
| 256 chars | 77 / 75 | 5 (6.5%) | 16.80 ms |
| 512 chars | 76 / 74 | 10 (13.2%) | 18.26 ms |
| 1,024 chars | 75 / 73 | 34 (45.3%) | 20.26 ms |
| 2,048 chars | 75 / 73 | 57 (76.0%) | 23.18 ms |

The 68-character baseline smoke was 76 frames / 74 edits, 4 dropped equivalents
(5.3%), p95 17.12 ms. This points to text length in the active `RenderEditable`
as a primary cost. A simple multi-`TextField` split is unsafe because it would
break selections and gestures across segment boundaries. Keep one logical
selection and document source while bounding the rendered editing window; the
prototype still needs to prove IME and cross-boundary behavior before replacing
the current editor.

### Stage-budget measurement correction (2026-09-23)

The plan requires **<1% of frames exceeding the device refresh budget**. The
previous harness instead counted `ceil(totalSpan / 16.667 ms) - 1` as dropped
frames, regardless of the active refresh rate. Flutter documents that build
and raster stages can each fit the budget while total latency exceeds it:
[SchedulerBinding.addTimingsCallback](https://api.flutter.dev/flutter/scheduler/SchedulerBinding/addTimingsCallback.html).
Thus the historical 21.4% figure and the size-sweep percentages cannot establish
the plan's stage-budget failure. Total-span measurements remain useful latency
evidence; they are not discarded or silently relabeled as passing.

Both P12 frame harnesses now share a regression-tested calculation: count a
sample once if **build OR raster duration** exceeds `1000 / refreshRate` ms.
Report individual stage counts, p95/max stage durations, and p95/max total
latency separately. Use the test view's display rate, fail a run if sampled rates
change, reject empty/invalid data, exclude delayed warmup timing batches, and
require strictly <1% over-budget samples. The rich diagnostic now pumps one response per edit, removing artificial
idle-frame dilution. Its fixture includes an actual `#strong[Formatted]` span
and asserts the virtual-plain route is ineligible; text, formatting and the
Typst header must survive all edits. It mounts the renderer directly and uses
controller updates, so it does not prove production keyboard/IME behavior.

The regression first failed with total-span classification (two false failures
for frames whose stages fit the budget), then passed with stage classification.
Focused metrics/editor suite: **97 tests passed**. Targeted Dart analyzer: clean.
No production editor code was changed for this correction.

The connected device identifies as **Nothing A024** (the "A24" label in this
tracker). A 20-second profile smoke observed **90 Hz / 11.111 ms**, 74 edits and
76 timing samples: **0 stage-budget violations**, versus 48 samples over the
latency budget. Build p95/max: 7.595/10.359 ms; raster p95/max: 6.161/7.257 ms;
total-span p95/max: 15.827/17.162 ms. This smoke preceded warmup-batch filtering
and is diagnostic only. The filtered five-minute result below supersedes this short smoke.

Commands (synthetic fixtures in isolated `.profiletest`, production data untouched):

```bash
flutter test --no-pub test/editor_frame_metrics_test.dart test/virtual_plain_editor_test.dart test/rich_editor_test.dart
flutter drive --no-pub --no-dds --profile -PtylogProfileSuffix=.profiletest --device-id 000251565001005 --driver=test_driver/integration_test.dart --target=integration_test/p12_virtual_plain_frame_native_test.dart
```

P12 remains open until the corrected device gate, production-input/formatted-note
coverage and cross-row editing regressions pass. A bounded-window rewrite is
conditional on stage profiling; the previous instruction requiring total-span
p95 <=16.67 ms as a renderer acceptance gate was not the main plan's UI contract.
Total latency continues to be reported explicitly, so this correction cannot
hide input lag.

#### Corrected device results

| Workload | Duration | Refresh / budget | Edits / samples | Over-budget frames | Build p95 / max | Raster p95 / max | Total-span p95 / max |
|---|---:|---|---|---|---|---|---|
| Virtual plain, 900 rows, initial active paragraph 68 chars | 300 s | 90 Hz / 11.111 ms | 1,098 / 1,098 | **83 (7.559%)**, all build | 11.477 / 14.962 ms | 6.049 / 9.775 ms | 18.646 / 22.984 ms |
| Formatted long note, rich renderer | 20 s | 120.000008 Hz / 8.333 ms | 56 / 56 | **56 (100%)**; build 56, raster 2 | 100.775 / 102.786 ms | 7.168 / 10.099 ms | 109.312 / 111.034 ms |

Both fail. The plain run also misses the existing 1,100-edit requirement by two;
the rich smoke misses the 60-edit minimum (three edits/second). Neither sample
minimum nor the <1% stage-budget threshold was relaxed. The plain run records
945 total-span budget exceedances; these are separate latency observations,
not 945 dropped frames. Each workload observed a stable Flutter display rate;
these runs use different device-selected rates and are not a controlled
plain-versus-rich speed comparison.

The formatted run passed text/formatting/header round-trip assertions before
failing the throughput assertion. The initial plain full run stopped at its
edit-count assertion before source checks; the earlier plain smoke passed those
checks. Source assertions now run before performance expectations in both
harnesses so a failing frame gate cannot hide correctness results.

The rich smoke command is the same driver command above with
`--target=integration_test/p12_editor_frame_native_test.dart`
`--dart-define=P12_DURATION_SECONDS=20`. Its 100% violation rate already supplies
a failing diagnostic; spending another five minutes on it would not establish
acceptance. The default remains 300 seconds for the eventual full gate.

Next: profile the UI/build phase separately for the growing virtual row and
formatted document; apply a fix at the expensive layout/rebuild operation and
repeat the matching diagnostic. The formatted renderer is the larger observed
stall. Do not infer that a GPU/backend migration or merely relaxing the budget
would solve it. Full P12 closure still requires P12h editing and production-input
coverage plus passing five-minute runs.

#### Formatted-renderer layout attribution (2026-09-23)

An opt-in `P12_TRACE=true` run of the same formatted fixture enables Flutter's
widget-build and render-layout timeline events. The driver now writes response
data even when the performance assertion fails, preserving the evidence in
`build/integration_response_data.json` instead of losing the failing trace.
Use `--dart-define=P12_DURATION_SECONDS=10 --dart-define=P12_TRACE=true` with
the formatted-note driver command. Instrumented timings are diagnostic only;
normal acceptance runs leave tracing disabled.

The trace contained 29 edit-response frames at a stable 90 Hz. All 29 violated
the build budget (build p95 98.972 ms; raster p95 6.770 ms). Aggregating paired
begin/end timeline events identifies **29 `RenderEditable` layouts, 2,157.03 ms
total, 74.38 ms mean, 81.83 ms maximum**. Almost all of that time is inside
`RenderEditable` itself (2,149.37 ms exclusive of nested timeline events).
By comparison, `_Editable` widget updates total 74.84 ms across the run and
paint totals 230.12 ms. This narrows the main problem to text layout rather than
rebuilding the toolbar or GPU raster work. Source/formatting/header checks pass;
the throughput and frame gates still fail.

A temporary host probe ruled out redundant adjacent-style runs as a useful fix:
the 900-line formatted fixture already produces no more than three text spans,
with source, composition offsets and protected widgets preserved. No span-merging
implementation was added, and the throwaway probe was removed. Production
editor behavior remains unchanged by this profiling checkpoint.

Next implementation: bound the amount of formatted text laid out for an edit,
while preserving the controller's complete source and global selection/IME
semantics. Cross-row gestures, boundary deletion, composition, paste and undo
must be tested before enabling a replacement. P12 remains open; a profiling
checkpoint is not a performance fix.

#### Isolated editor replacement evaluation (2026-09-23)

Neither evaluated replacement has established full acceptance. The initial profile
probes use the same shared stage-budget metric and a formatted 900-row fixture,
with synthetic appends every 250 ms for 20 seconds. On Apple M4 Pro/macOS at a
stable approximately 120 Hz (8.333 ms stage budget):

| Editor/layout | Edits / frames | Over budget | Build p95 / max | Raster p95 / max |
| --- | ---: | ---: | ---: | ---: |
| Super Editor 0.3.0-dev.52, 900 paragraph nodes | 69 / 69 | 68 (98.55%) | 16.786 / 18.490 ms | 1.733 / 2.143 ms |
| Super Editor, one node containing all hard newlines | 70 / 70 | 70 (100%) | 36.198 / 36.715 ms | 1.059 / 1.132 ms |
| Flutter Quill 11.5.1, 900 paragraphs | 72 / 72 | 70 (97.22%) | 17.181 / 17.500 ms | 1.378 / 3.446 ms |

Plain-text integrity and diagnostic throughput assertions pass; all three frame
assertions fail. These are Mac diagnostics, not comparable controlled timings
against the prior Android baseline and not five-minute acceptance runs. Global
selection, IME, protected Typst atoms and source serialization were not ported.
No replacement is enabled and no candidate dependency was added to TyLog.

Source inspection explains why a package swap does not bound layout:
Quill's `RenderEditableContainerBox.performLayout` visits every child;
Super Editor's `SingleColumnDocumentLayout` places all components in a `Column`
inside a `SliverToBoxAdapter`. Neither evaluated configuration provides lazy
paragraph layout while preserving document-wide editing semantics.

Reproduce with `tool/editor_candidates/run.sh super_editor macos --no-dds`
or `tool/editor_candidates/run.sh flutter_quill macos --no-dds`. Add
`--dart-define=P12_SINGLE_PARAGRAPH=true` for the Super Editor one-node case.
The runner retains the generated project and failing driver JSON in a temporary
directory; it never changes the production package or vault. Its README records
the fixture difference for Quill's unmeasured single-paragraph variant.

Runner verification produced mixed results: Super Editor again failed (69/69
over budget; build p95 15.689 ms). Quill's fresh-project rerun passed the short
diagnostic (75 edits/frames, 0 over budget; build p95/max 5.001/5.257 ms,
raster p95/max 0.622/1.734 ms, 120 Hz). The fixture, editor source, metric helper,
Quill version and relevant transitive versions match the initial failing run;
the new project omits template-only icon/lint dependencies and lowers the
declared minimum Dart SDK from 3.13.4 to 3.12.2. The cause of this
timing difference is not established. Do not discard either result or infer
that the failure is fixed. Both runner commands execute end to end and preserve
driver results on success and failure.

P12 remains open. Before choosing a replacement, reconcile Quill's mixed
results under controlled viewport, focus and host load, then prove source and
editing parity. A layout change must retain document-wide selection/composition;
independent paragraph fields alone cannot establish that. A short synthetic
Mac pass does not close the full production or five-minute device gates.

## Frame diagnostics are opt-in (2026-09-26)

`p12_editor_frame_native_test`, `p12_virtual_plain_frame_native_test` and
`p12_editor_render_trace_native_test` now skip unless run with
`--dart-define=P12_FRAME_GATE=true`. They are the P12 device gate, not host
regression checks: in `make verify` the formatted run failed on a macOS debug
build (71 edits, 100% over budget), which is the known open P12 result and
kept U0's verify red. Run them on the A24 profile build for P12 acceptance.
The double `removeTimingsCallback` assertion on the failure path is fixed.

## A24 rerun on main (2026-09-27)

Isolated `.profiletest` package, `P12_FRAME_GATE=true`, production app left
installed and idle.

| Run | Refresh / budget | Edits / frames | Over budget | Build p95 | Raster p95 |
|---|---|---|---|---|---|
| Plain 900-row, 300 s (device-chosen rate) | 120 Hz / 8.333 ms | 1,106 / 1,106 | **290 (26.22%)**; build 278, raster 18 | 10.343 ms | 7.106 ms |
| Plain, 1,024-char active row, 20 s, min rate pinned to 120 Hz | 120 Hz / 8.333 ms | 74 / 74 | 28 (37.8%) | 11.244 ms | 6.756 ms |
| Same, `TextField(decoration: null)` + outer padding | 120 Hz / 8.333 ms | 74 / 74 | 31 (41.9%) | 10.755 ms | 7.279 ms |

The earlier 7.56% result was taken at 90 Hz (11.1 ms budget); at 120 Hz the
same build cost fails by a wider margin. Removing the InputDecorator does not
change build time (within run-to-run noise), so it was reverted: the cost is
laying out the growing paragraph itself (~10 ms for ~1k chars on this device).
Both plain and formatted gates therefore need the bounded-layout (P12k)
change; no cheaper widget-level fix remains. The device refresh setting was
restored (`min_refresh_rate=0.0`) after the pinned runs.

### Plain-editor frame attribution on A24 (2026-09-27)

`P12_TRACE=true` now also works for `p12_virtual_plain_frame_native_test`
(build/layout profiling inside `binding.traceAction`). 10 s traced run, 1,024-char
active row, 31 edit frames (means include profiling overhead):

| Phase | Mean per edit frame |
|---|---:|
| BUILD | 1.1 ms |
| LAYOUT (of which `RenderEditable` 3.8 ms) | 4.4 ms |
| SEMANTICS | 2.6 ms |
| PAINT + COMPOSITING | 1.6 ms |
| Raster (`GPURasterizer::Draw`, raster thread) | 4.2 ms |

Semantics is enabled by the engine on this phone (`platformDispatcher.semanticsEnabled=true`).
The user-installed RustDesk input service is an accessibility service; with it
temporarily disabled (user-approved, restored immediately after) a 20 s smoke
still built semantics (2.6 ms/frame) and measured build p95 11.6 ms at 90 Hz
(10.8% over budget), so another system service also turns semantics on. This is
the device's real operating condition. Conclusion: the active-row cost is the
paragraph's own layout plus semantics; a bounded window removes whole-document
layout (formatted editor, ~75 ms) but cannot remove per-paragraph cost. P12k
proceeds (user decision 2026-09-27) with the gate re-measured afterwards.

## P12k design (2026-09-27)

Goal: an edit lays out a bounded window of blocks, not the whole document,
without changing `TyLogEditingController`, the document model or source bytes.

- `TyLogWindowController` (a `TextEditingController`) is what the `TextField`
  edits. Its text is `main.text.substring(start, end)` where `[start, end)`
  covers whole blocks. A user edit is spliced into the main controller's
  global value (`start` + window offsets), so every existing edit path —
  formatting, Enter/Backspace across blocks inside the window, paste,
  composition, undo/redo — runs unchanged on global offsets. Text outside the
  window is untouched by such an edit, so the new window end is
  `main.text.length - tail`.
- Recentering: the window always covers the selection plus a margin of blocks
  and is recentered only when the selection nears an edge and no composition
  is active. Select-all or a selection spanning the whole note expands the
  window to the whole document (correct, slow, rare).
- Spans: `buildTextSpan` renders only the window's blocks via a block-range
  variant of the existing `_textSpan`, so composing and chip rendering are the
  same code.
- Outside the window each block is a read-only `RichText` with the same
  style and strut inside one scroll view, laid out once and reused. Tapping one
  moves the window there and places the caret via its paragraph hit test.
- Guarded by `kEnableEditorWindow`; enabled only after the existing rich-editor
  host suite passes against it, then the A24 formatted gate is rerun.

## P12k line window: formatted A24 gate PASS (2026-09-27)

The first, block-aligned window did not help: the 900-row formatted fixture is
one Typst paragraph (single newlines), so the window was the whole note
(`RenderEditable` still ~70 ms). The window is now `[start, end)` of whole
lines around the selection (margin 6 lines, capped at 2·6+8 line breaks, and
recentered when appends grow it), spans for any range are sliced from the
existing block spans, and static text outside is laid out once in 20-line
chunks. Recentering never happens during an IME composition.

Host: 8 window unit tests (including byte-identical source against direct
edits for typing, paragraph split, paste with markup, backspace merge, and
appends into one 900-line paragraph) plus the full rich-editor suite run
windowed (`test/rich_editor_windowed_parity_test.dart`, 91/91) and normally
(91/91).

A24 profile, isolated `.profiletest`, `P12_WINDOW=true`, 300 s:

| Run | Refresh / budget | Edits / frames | Over budget | Build p95 / max | Raster p95 / max |
|---|---|---|---|---|---|
| Formatted, no window (20 s diagnostic) | 120 Hz / 8.333 ms | 56 / 56 | 100% | 103.7 ms | 8.7 ms |
| Formatted, block window (20 s) | 120 Hz / 8.333 ms | 56 / 56 | 100% | 100.4 ms | 8.5 ms |
| Formatted, line window, uncapped (300 s) | 120 Hz / 8.333 ms | 1,026 / 1,026 | 92.8% | 24.3 ms | 3.9 ms |
| Formatted, line window, capped (300 s) | 120 Hz / 8.333 ms | 1,048 / 1,048 | 0.29% | 6.0 / 8.8 ms | 6.6 / 8.2 ms |
| **Formatted, line window, capped (300 s, final)** | **120 Hz / 8.333 ms** | **1,049 / 1,049** | **0 (0.0%)** | **4.75 / 8.20 ms** | **4.42 / 7.95 ms** |

The harness's formatted edit minimum was aligned with the plan (≥60 edits in
300 s; it had copied the plain workload's 1,100). Source/format/header
assertions pass. Still open for P12: enable the window in production after a
real-keyboard/IME check (macOS native editor test and A24 hands-on), and the
plain 900-row gate (currently `VirtualPlainEditor`, 26.2% over at 120 Hz).

## Window regressions resolved; plain gate still fails (2026-09-27)

The scroll-centre layout (needed so the editing field is always built for
the IME) regressed the formatted gate (3.3% over at 120 Hz; 4.4% with scroll
compensation off, so compensation was not the cause). Cause: the static list
above the window is built in reverse, so each chunk added by re-centring
shifted every index and rebuilt every visible chunk. Stable offset keys with
`findChildIndexCallback` (8de82fc, drafted by local ornith) fixed it. With the
production app force-stopped during the run (its sync polls compete for CPU):

| Run (A24 profile, 300 s, `P12_WINDOW`) | Refresh | Edits | Over budget | Build p95 | Raster p95 |
|---|---|---:|---:|---:|---:|
| Formatted, keyed chunks | 120 Hz | 1,049 | **0.095%** (1 frame) | 5.6 ms | 3.9 ms |
| Plain growing paragraph, keyed chunks | 120 Hz | 1,052 | 89.8% | 12.6 ms | 5.6 ms |

The plain workload types into one paragraph for 5 minutes (68 → ~1,120
chars). A single `RenderEditable` paragraph of that length costs ~3.5 ms layout
plus ~2.6 ms semantics per frame on this device, and the window adds its
neighbouring lines; the old one-field-per-line editor measured 26%. Passing it
needs long paragraphs split into independently laid-out display segments while
keeping one logical paragraph (a further editor change), or a plan decision on
that workload. The run also missed the plan's 1,100-edit minimum by 48 (the
harness paces 4 edits/s).

## Plain gate passes with display units (2026-09-28)

Long lines are split into display units (~100 chars, broken after a space); the
editing window is whole units, recenters past 400 chars, refills to half that
(fa2f8e2, 48242a5).
Typing inside one text run now splices the run's string instead of converting the
whole block to per-character units: host edit 2.7 ms -> 0.36 ms, A24 per-edit
12.5 ms -> 3.5 ms (7c22cdb). The windowed field has no InputDecorator, whose
dry-baseline pass was a second text layout per keystroke.

The harness edits on a fixed 4 Hz schedule: edit *n* at start + *n* x
250 ms. The relative pump plus frame wait capped runs
near 1,090 edits regardless of editor cost; the build-time frame criteria are
unchanged. P12_TRACE now collects in-process through FlutterTimeline, since a
trace action cannot reach the VM service on the device.

| Run | Refresh | Edits | Over budget | Build p95 | Raster p95 |
|---|---:|---:|---:|---:|---:|
| Line window (previous) | 120 Hz | 1,052 | 89.8% | 12.6 ms | 5.6 ms |
| Units, 1,200-char cap | 90 Hz | 1,053 | 34.1% | 12.8 ms | 5.9 ms |
| Units, 600-char cap | 120 Hz | 1,068 | 2.25% | 8.0 ms | 5.6 ms |
| Units, 400-char cap, run-splice | 120 Hz | 1,092 | 0.27% | 7.2 ms | 5.6 ms |
| **Same, fixed 4 Hz schedule (final)** | **120 Hz** | **1,200** | **0.5%** | **7.0 ms** | **5.6 ms** |

The plain gate passes (>=1,100 edits, <1% over budget, source/header assertions
pass). The formatted gate must be rerun on an idle phone with the 400-char
window: a run during foreground use of another app measured 3.5%, and the
previously passing code measured 3.3% in the same conditions. P12 stays open
until that rerun and the real-keyboard/IME check.

