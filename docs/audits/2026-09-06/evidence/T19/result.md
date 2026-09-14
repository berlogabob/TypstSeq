# T19 verification

Date: 2026-09-09

Implementation: `KnowledgeScreen` subscribes to the injected `WorkspaceController` (`Listenable`) and uses readiness/revision callbacks to show `Indexing search…`, rerun the current query after readiness/revision changes, distinguish `No matches`, invalidate delayed generations, and remove the listener on dispose. `HomeScreen` wires the existing workspace directly.

Commands and results:

- `flutter test test/widget_test.dart --plain-name 'KnowledgeScreen' --reporter expanded` — 5 passed (readiness refresh, empty result, delayed old query, disposal, saved-search status).
- `flutter test test/widget_test.dart --plain-name 'saved searches stay current across saves, delete, and failure' --reporter expanded` — 1 passed.
- `flutter test test/widget_test.dart --plain-name 'saved-search controls stay locked during a delayed write' --reporter expanded` — 1 passed.
- `flutter analyze lib/knowledge_screen.dart lib/app_mobile.dart test/widget_test.dart` — no errors; 3 existing infos (`prefer_final_fields`, two `use_build_context_synchronously`).
- `git diff --check` — clean.
- `graphify update .` — completed.

Final SHA-256:

- `lib/knowledge_screen.dart`: `1a3f3a756271c56f8830e891e05f61d3a022f71e263ae73193379622950fec79`
- `lib/app_mobile.dart`: `2b13e49637417a344d7898bc027f63603f857e7e6eef4abeaf09a3065badae5a`
- `test/widget_test.dart`: `b3699c3149d7a686ea816530b34c9c47cfec99beaa8c9407b442763f0a83c2b6`

## Coordinator review addendum

An independent review found that replacing `searchState` while the screen was mounted did not resample an already-published ready/revision value. `didUpdateWidget` now resamples whenever the state or either callback changes. The added replacement-state regression brings the focused `KnowledgeScreen` run to **6 passed**; the integrated T27 suite also passes this check. Final combined file fingerprints are recorded in T21/T27 evidence.

Post-review addendum (2026-09-09): `flutter test test/widget_test.dart --plain-name 'KnowledgeScreen' --reporter expanded` — 6 passed, including replacement of a non-ready screen with an already-ready search state. `KnowledgeScreen` now resamples callbacks/listener state in `didUpdateWidget`.
