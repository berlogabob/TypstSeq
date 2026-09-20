# P22 progress — bounded graph traversal

Status: RUNNING

Replaced recursive path enumeration with deterministic breadth-first traversal. It accepts at most 200 nodes, examines at most 500 edge rows across queries, and caps depth at 10. Missing seeds return no nodes. High-fanout and cycle tests verify these bounds. Graph UI and export wiring remain outstanding; SQL execution latency at a high-degree hub still needs measurement.

Added deterministic SVG export with stable node/edge ordering and XML label escaping.

Evidence:

- `flutter test test/database/bounded_neighborhood_test.dart` — cycle and depth ordering pass.
- `flutter analyze lib/database/tylog_database.dart test/database/bounded_neighborhood_test.dart` — clean.
- `flutter test test/retrieval_graph_svg_test.dart` — deterministic export and escaping pass.

Edge upsert/delete APIs now enforce the existing foreign-key constraints and are covered by the neighborhood test.

Full regression after schema and graph changes: `flutter test` — 707 passed, 2 skipped.

Acceptance correction (2026-09-20): existing unit evidence does not close the full milestone. See the execution ledger for remaining integration and native checks.
