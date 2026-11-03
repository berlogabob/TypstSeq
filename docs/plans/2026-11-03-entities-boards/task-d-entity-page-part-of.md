# Task D: entity page "Part of" and "Contains"

Depends on Task A (NoteRef.partOf, childrenByParent).

- On any non-structural note page (where linked references are shown; see lib/widgets/linked_references.dart and how app_mobile.dart decides isEntity via structuralNoteKinds ~5724): add a "Part of" row of chips (icon via iconForKind + title, tap opens the parent, x removes) with an add button that uses the existing entity chooser (`_chooseEntity` / `_chooseNote` in lib/app_mobile.dart ~4305) and allows creating a new entity.
- Writes are surgical: update only `properties.part_of` via replaceNoteHeader with the current NoteMetadataDraft (pattern: MagicAction.project branch in lib/app_mobile.dart ~4314). Store parent ids, not titles. Never touch the body.
- "Contains" section: children from childrenByParent, grouped by kind with kind icon + count, each tappable.
- Magic action "Project" becomes "Part of…": picks any entity (not only kind project) and appends to part_of instead of overwriting `project:`. Keep reading legacy project:.
- No layout shift: sections reserve space or use AnimatedSize (memory rule tylog-ui-no-layout-shift).
- Tests: adding/removing a parent rewrites only the header (compile the result); Contains lists a multi-parent child under each parent; widget test for chips.
- Done when tests pass, analyze clean. Do not commit. Report.
