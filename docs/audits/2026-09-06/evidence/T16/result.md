# T16 result

Date: 2026-09-09

- Focused regression: `flutter test test/workspace_controller_test.dart --plain-name 'rating and deletion during a scan queue one follow-up without cancelling'` — 1 passed, 0 failed.
- Relevant suites: `flutter test test/workspace_controller_test.dart test/articles_shelf_test.dart` — 54 passed, 0 failed.
- Targeted analysis: `flutter analyze lib/app_mobile.dart lib/workspace_controller.dart test/workspace_controller_test.dart test/articles_shelf_test.dart` — no issues.

Article deletion now uses `refreshIndex(always: true)`, which queues behind an active scan instead of invoking cancelling `rebuildIndex`. Delete failures and failure to move a dirty open article are visible and do not report success. Rating continues through `mutateNote`, sharing the coalesced refresh. The gated regression confirms rating and deletion during an active scan produce no cancellation and publish the final rating/deletion state after release; confirmation cancellation remains an early no-op.

Scoped diff SHA-256: `6c30ac573b2ca3103fb54d6d129ca13d9e6a4ddc58bc84f6068034bdcf4018a3`; plain counts: app_mobile 208+/106-, controller 535+/176-, controller tests 1001+/187- (includes accepted prior changes).

Known limit: direct HomeScreen dialog failure/cancellation rendering remains covered by existing shelf callback tests; native storage failure requires platform-backed widget setup.
