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
