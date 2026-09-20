# P22 progress — bounded graph traversal

Status: DONE

Added a recursive SQLite neighborhood query with a depth cap, path-based cycle detection, and deterministic `(depth, id)` ordering. Cyclic evidence graphs therefore terminate predictably and return a bounded result suitable for a graph view.

Added deterministic SVG export with stable node/edge ordering and XML label escaping.

Evidence:

- `flutter test test/database/bounded_neighborhood_test.dart` — cycle and depth ordering pass.
- `flutter analyze lib/database/tylog_database.dart test/database/bounded_neighborhood_test.dart` — clean.
- `flutter test test/retrieval_graph_svg_test.dart` — deterministic export and escaping pass.

Edge upsert/delete APIs now enforce the existing foreign-key constraints and are covered by the neighborhood test.
