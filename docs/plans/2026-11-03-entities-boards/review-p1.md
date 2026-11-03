# P1 review findings (codex terra, 2026-11-03)

1. **Issue status writes can lose edits and leave the board stale** — [entity_board.dart:143](/Users/berloga/Documents/GitHub/TypstSeq/lib/widgets/entity_board.dart:143). The drop handler writes directly to storage, bypassing the open editor buffer and serialized note writes. A later autosave can overwrite the status, or the direct write can race another save. It also waits for a mutation refresh without scheduling one. Use `workspace.mutateNote` and its refresh path.

2. **Namespace migration removes existing parents** — [namespace_migration.dart:66](/Users/berloga/Documents/GitHub/TypstSeq/lib/namespace_migration.dart:66). Migrating a page replaces its entire `part_of` list with the namespace parent. Merge the new parent into the current list instead.

3. **A namespace alias can create a self-parent** — [namespace_plan.dart:170](/Users/berloga/Documents/GitHub/TypstSeq/packages/tylog_core/lib/src/namespace_plan.dart:170). A page titled `A/B` with alias `A` can be selected as its own ancestor; applying the plan rewrites it twice and makes it its own parent. Exclude IDs already assigned to descendant paths and reject cycles.

4. **Kind changes may not sync** — [workspace_controller.dart:761](/Users/berloga/Documents/GitHub/TypstSeq/lib/workspace_controller.dart:761). Writing the registry neither marks the shared settings file as pending nor queues cloud sync, so changing an icon alone may never reach another device. Mark the actual shared path pending and queue sync after a successful write.

5. **Valid headers can block the entire namespace migration** — [namespace_migration.dart:43](/Users/berloga/Documents/GitHub/TypstSeq/lib/namespace_migration.dart:43). The preflight requires `title` and `aliases` on individual lines and the aliases tuple on one line. Valid headers can omit `aliases` or use a multiline tuple, causing the batch to stop. Insert missing fields and use balanced parsing for existing values.

6. **Logseq import applies migration without the required dry run** — [vault_import_flow.dart:596](/Users/berloga/Documents/GitHub/TypstSeq/lib/app_mobile/vault_import_flow.dart:596). Import can rewrite existing ancestor notes immediately, without showing changes and skipped titles for confirmation. Present the plan before applying it.

7. **Projects containing only issues cannot open a board** — [app_mobile.dart:5911](/Users/berloga/Documents/GitHub/TypstSeq/lib/app_mobile.dart:5911). The button is shown only when tasks exist, even though marker issues also belong on the board. Include `issuesForEntity` in the visibility condition.

8. **Parent boards omit tasks assigned to descendant projects** — [board.dart:167](/Users/berloga/Documents/GitHub/TypstSeq/packages/tylog_core/lib/src/board.dart:167). A task in a daily note assigned to a child project fails both the root-ID comparison and the containing-note check. Resolve `task.project` and match it against the descendant IDs.

9. **Legacy project parents cannot be removed** — [entity_relationships.dart:98](/Users/berloga/Documents/GitHub/TypstSeq/lib/widgets/entity_relationships.dart:98). The delete action is disabled for a parent supplied by the legacy `project` field, contrary to the removable-chip requirement. On removal, surgically clear or migrate that field as well as any matching `part_of` entry.

10. **Reordering can discard newer board fields** — [board.dart:69](/Users/berloga/Documents/GitHub/TypstSeq/packages/tylog_core/lib/src/board.dart:69). Parsing retains unknown top-level keys but drops unknown keys inside `scope` and `columns`; the next reorder writes the reduced object back. Preserve those nested keys through serialization.

11. **Status metadata can be written into a comment** — [issues.dart:26](/Users/berloga/Documents/GitHub/TypstSeq/packages/tylog_core/lib/src/scanner/issues.dart:26). For an issue line ending in a Typst `//` comment, the appended metadata is commented out, even though the scanner’s regex can still read it as a status. Insert it before a trailing comment or reject the edit, and ignore commented metadata when scanning.
