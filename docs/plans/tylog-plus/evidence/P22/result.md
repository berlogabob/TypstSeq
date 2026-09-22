# P22 progress — bounded graph traversal

Status: HOST ACCEPTED / DEVICE VERIFIED / TARGET REVIEW

Replaced recursive path enumeration with deterministic breadth-first traversal. It accepts at most 200 nodes, examines at most 500 edge rows across queries, and caps depth at 10. Missing seeds return no nodes. High-fanout and cycle tests verify these bounds. Graph UI and export wiring remain outstanding; SQL execution latency at a high-degree hub still needs measurement.

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
`tylog-graph.svg` `image/svg+xml` payload and returned after dismissal, proving
the app reaches the native share intent. Selecting and validating a target app
remains a manual platform check.
# P22 progress — bounded graph traversal
