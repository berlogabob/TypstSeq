# P22 progress — bounded graph traversal

Status: MAC DIAGNOSTICS PASS / ANDROID LATENCY AND REAL-VAULT ROUTE OPEN

Replaced recursive path enumeration with deterministic breadth-first traversal.
It accepts at most 200 nodes, consumes at most 500 returned edge rows across
queries, and caps depth at 10. Missing seeds return no nodes. This bounds the
Dart traversal, not SQLite's internal scans: the ordered endpoint lookup uses
temporary sorting/deduplication and may inspect all matching hub edges.
Graph UI/export and native Android share handoff are implemented and checked.
Synthetic SQL scale and Mac GraphView measurements are below; Android latency
and the complete real-vault route remain open.

Added deterministic SVG export with stable node/edge ordering and XML label escaping.

Evidence:

- `flutter test test/database/bounded_neighborhood_test.dart` — cycle and depth ordering pass.
- `flutter analyze lib/database/tylog_database.dart test/database/bounded_neighborhood_test.dart` — clean.

The Flutter graph surface now applies the same interactive ceiling before
layout: at most 200 nodes and 500 edges, with the current path and highest
degree nodes retained deterministically. `flutter test test/graph_test.dart`
passes 18 tests including the cap ordering check. This bounds rendering cost;
database neighborhood selection and graph export remain separate paths.
- `flutter test test/retrieval_graph_svg_test.dart` — deterministic export and escaping pass.

Graph UI now exposes an `Export SVG` action. It uses the bounded graph, a
deterministic 1000×1000 layout, escaped labels, and the existing platform share
sheet as `tylog-graph.svg`. The action is wired from `HomeScreen` into
`GraphView`; graph tests still pass. Full native share-sheet acceptance remains
device-gated.

The widget-level export test now verifies the visible `Export SVG` action calls
the share seam with the bounded graph (19 graph tests pass). Only the native
share target/file handoff remains device-gated.

P22d closes the host UI portion: the graph surface applies the 200-node/500-edge
ceiling before layout, supports node open/fit actions, and exposes the bounded
`Export SVG` action. The remaining P22 acceptance item is native share-target
and file-handoff verification.

Edge upsert/delete APIs now enforce the existing foreign-key constraints and are covered by the neighborhood test.

## Host query-plan gate (2026-09-21)

The bounded-neighborhood test runs SQLite `EXPLAIN QUERY PLAN` for the
two-endpoint edge lookup used by traversal. Both `from_node_id` and
`to_node_id` resolve through their dedicated indexes
(`idx_edges_from_node_type` and `idx_edges_to_node_type`) in the in-memory
Drift database. The host SQL plan check passes; native graph interaction and
share-target verification remain device-gated.

Full regression after schema, graph, editor, reader, retrieval, and report changes: `flutter test --no-pub` — 736 passed, 2 skipped.

Acceptance correction (2026-09-20): existing unit evidence does not close the full milestone. See the execution ledger for remaining integration and native checks.

Sequential host rerun: bounded traversal, SQLite query plans, graph interaction,
and deterministic SVG export passed 24 tests. Native share-target verification
remains device-gated.

## A24 native handoff (2026-09-22)

`flutter drive --profile --target=integration_test/graph_share_native_test.dart`
passed on A24 (`000251565001005`). The Android chooser opened for a
`tylog-graph.svg` `image/svg+xml` payload. Selecting the installed Nextcloud
target completed the flow and returned to the test app with `Test finished.`
This closes the native target/file-handoff check for the available target.

## Synthetic high-degree traversal timing (2026-09-23)

`flutter test --no-pub --dart-define=TYLOG_RUN_SCALE_BENCHMARKS=true
test/database/bounded_neighborhood_benchmark_test.dart --reporter expanded`
passed on macOS 26.6.2, Apple M4 Pro arm64, Flutter 3.47.5. The benchmark is
opt-in and skipped in the default test run.
The focused benchmark builds an in-memory SQLite database with 100,000 synthetic
nodes and 1,000,000 edges incident to one hub, then times 40 calls to the actual
`boundedNeighborhood` method after five warmups. Returned node count and seed
are checked on every run. The helper's configured limits are 200 nodes and 500
examined edges. The opt-in rerun measured host method latency at p50 68.951 ms,
p95 70.295 ms, max 70.665 ms.

This measures SQLite plus traversal helper latency on synthetic host data. It
does not measure Flutter layout, rendering, device latency, or the plan's full
interactive graph-view p95 gate; those acceptance checks remain open.

## macOS profile GraphView interaction timing (2026-09-23)

`flutter drive --no-pub --no-dds --profile
--driver=test_driver/integration_test.dart
--target=integration_test/p22_graph_latency_native_test.dart -d macos` passed.
The integration test creates a synthetic note graph, applies the same
`boundGraphForLayout` ceiling as the app, then uses the production
`GraphView` for 30 cold mounts and 30 node selections. On the Apple M4 Pro
arm64/macOS 26.6.2 profile build, the 200-node/500-edge graph mount-to-ready
latency was p50 149.497 ms, p95 152.286 ms, max 158.819 ms. Node-selection
latency was p50 105.252 ms, p95 111.655 ms, max 111.787 ms. Both measured p95s
are below the 500 ms target.

The app builds these visible graphs from its legacy `VaultIndex` via
`buildLocalNoteGraph`/`buildNoteGraph`, then bounds the result in
`_memoizedGraph`; this path does not call `TyLogDatabase.boundedNeighborhood`.
This acceptance covers macOS profile GraphView interaction only. Android
interaction latency and the full real-vault graph route remain unmeasured.

### Contract-sized rerun (2026-09-24)

The plan requires at least 100 frequent-operation samples. The test now records
100 mounts and 100 selections plus raw driver data. The same profile command
passed: mount p50/p95/max **144.835/150.603/158.356 ms**; selection
**105.536/111.667/111.838 ms**. Raw values are retained in
[mac-graph-100-samples.json](mac-graph-100-samples.json). These conservative
wall-clock measurements include `pumpAndSettle`'s polling delay; selection
means the graph's visible node selection, not opening a note. Ollama inference
was unloaded before measurement. The app foreground request reported failure,
although the native test completed; this is not manual foreground UX evidence.

Local `ornith-1.5:9b` drafted the minimal sample-count/raw-report change. The
coordinator reviewed it and ran analysis (clean) and the native check. The
focused graph/traversal/export/frame-metric regression passed 28 tests, with
the million-edge benchmark skipped by default. Full milestone acceptance still
requires Android timing and the real-vault route.

## Read-only real-vault graph rehearsal (2026-09-25)

The opt-in native test scans the verified backup through a storage adapter that
rejects every write/delete, mounts `HomeScreen` with an in-memory database,
switches through the actual Graph view menu, and opens a selected note. The
backup aggregate was 6,298 notes. Navigation succeeded with zero vault mutation
attempts. The 6.40-second scan is reported separately from UI timing.

The verified-backup aggregate manifest matches its earlier local manifest after
the run: total bytes, file count, and aggregate corpus digest are unchanged.

Across 100 profile samples per graph mode, p95 was **926 ms** for Concept map
and **689 ms** for All files, above the 500 ms target. A separate five-sample
diagnostic measured direct graph construction/bounding/layout at 105/1/6 ms for
Concept map and 44/9/5 ms for All files. The UI samples switch modes between
operations; these stage timings do not account for the full HomeScreen rebuild.

Flutter reported `Failed to foreground app; open returned 1` during native
runs. The 100-sample timing is retained as a failure signal, not accepted as a
valid interactive performance result. A later caffeinated 100-sample attempt
stalled before producing measurements and was stopped. Raw paths, source text,
titles and per-file hashes are excluded from the committed report. The verified
backup remains unchanged; the read-only adapter recorded zero write/delete
attempts.

Reproduce with `TYLOG_PRIVATE_GRAPH_ROOT` set to the private backup root:

```sh
FLUTTER_TEST=true TYLOG_PRIVATE_GRAPH_ROOT="$TYLOG_PRIVATE_GRAPH_ROOT" \
  flutter drive --no-pub --no-dds --profile \
  --driver=test_driver/integration_test.dart \
  --target=integration_test/p22_private_graph_native_test.dart -d macos
```

Use `--dart-define=P22_SAMPLES=5 --dart-define=P22_DIAGNOSE=true` for a short
stage diagnostic; it does not close a 100-sample gate. P22 stays open pending
valid foreground measurements, a graph performance fix if confirmed, and
Android timing.

## Mode-switch cost analysis (2026-09-26)

The route’s graph memoization had one cache entry. Alternating Concept map and
All files therefore discarded the previous mode’s bounded graph and rebuilt it
on every switch; the rehearsal also incremented `indexRevision`, defeating the
cache even when the vault was unchanged. The cache is now keyed by revision,
graph mode, focus, and current note, while retaining the existing 200-node and
500-edge bounds and graph semantics. The host widget regression test verifies
that returning to a mode in the same revision reuses its graph.

The private harness keeps the read-only storage adapter and zero-write
assertion, discards samples unless lifecycle, mode, selected node, graph
bounds, and settled-frame checks all pass, and reports valid count, p50, p95,
and max from frame timings through the first settled frame. Device numbers are
pending a permitted profile run.

## A24 real-vault graph gate (2026-09-27)

Harness fix: Codex's first version awaited `binding.endOfFrame`, which never
completes when the window cannot produce frames, so Mac runs hung. Sampling
now fails fast unless lifecycle is `resumed`, times each switch by wall clock
from the menu selection to the first settled frame showing the mode (graph
visible, no spinner, no scheduled frame, selected node, 200/500 bounds), and
caps each frame wait at 5 s (timeouts are invalid samples).

Android: `P22_HANDSHAKE=true` makes the `.profiletest` app create its external
dir; the host pushes a read-only copy of the verified backup vault. A24 profile
build, 6,298 notes, index scan 21.2 s (reported separately):

| Mode | Valid samples | p50 | p95 | max |
|---|---:|---:|---:|---:|
| Concept map | 100/100 | 30.5 ms | **45.7 ms** | 48.1 ms |
| All files | 100/100 | 34.6 ms | **46.3 ms** | 166.3 ms |

The All files maximum is the first, uncached switch; later switches in the
same index revision reuse the per-mode graph cache (6cfe660). Graph bounds
200 nodes / 458 edges; selecting a node and tapping Open navigated to that note
with its text read back; zero vault write/delete attempts. The Mac source
backup's full SHA-256 manifest (11,826 files) is byte-identical before and
after. Raw samples: [a24-private-graph-100-samples.json](a24-private-graph-100-samples.json).

A24 passes the 500 ms p95 gate. The macOS 100-sample run is still required
and needs an idle, unlocked Mac (the app must stay foreground).

## macOS real-vault graph gate (2026-09-27) — P22 DONE

Same bounded harness, macOS profile build (M4 Pro), verified backup vault
(6,298 notes) read through the write-rejecting adapter, app kept in front:

| Mode | Valid samples | p50 | p95 | max |
|---|---:|---:|---:|---:|
| Concept map | 100/100 | 16.9 ms | **17.7 ms** | 20.0 ms |
| All files | 100/100 | 15.4 ms | **15.9 ms** | 87.7 ms |

Node selection opened the intended note with its text read back, zero vault
write/delete attempts, and the backup's 11,826-file SHA-256 manifest is
byte-identical before and after. Raw samples:
[mac-private-graph-100-samples.json](mac-private-graph-100-samples.json).
With the A24 result above, every platform/mode has 100 valid samples under the
500 ms p95 gate; SVG export stays covered by the host export tests and the
native share run in `make verify` after the graph-cache change. P22 closes.
