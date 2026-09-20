# P11c — durable creation and import

Status: PASS (host)

Current page, project, article, daily-note, unresolved-link, picker, entity,
mention, reading-log, and Markdown-article creation routes now record the new
file through the workspace's SQLite persistence seam. The initial node,
immutable revision, outbox entry, and derived invalidation are committed before
the UI reports success. Appending a legacy journal now reuses the target's
durable node identity and parents one import revision to its latest revision;
the importer remains the sole database writer for that operation.

If initial persistence fails, the newly created file is removed and the error
propagates. An existing file is returned untouched. Startup performs this work
only when it creates the first daily note for that date.

Focused checks:

```text
flutter analyze lib/app_mobile.dart lib/app_mobile/markdown_import_flow.dart \
  lib/workspace_controller.dart test/workspace_controller_test.dart
No issues found

flutter test test/workspace_controller_test.dart test/widget_test.dart \
  test/markdown_article_import_test.dart test/import/legacy_import_runner_test.dart
133 tests passed
```

```text
flutter test
681 tests passed; 2 opt-in tests skipped
```

Independent Luna review found the legacy journal double-write interaction;
the final regression now starts with an existing durable node and proves the
append retains that identity with one parented import revision.
