# P12e result — latency acceptance

Status: HOST COMPLETE / DEVICE PENDING

Host acceptance uses the plan gates from `docs/plans/tylog-plus/plan.md` and runs 30 database startups plus 100 durable saves of 50 KB notes:

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
