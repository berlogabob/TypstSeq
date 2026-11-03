# Task A: project becomes an entity kind + part_of relation in the index

Read docs/plans/2026-11-03-entities-boards/README.md (P1) and CONTEXT.md "Engineering rules" first.

## Change
1. `packages/tylog_core/lib/src/models.dart`: move `'project'` from `structuralNoteKinds` to `entityNoteKinds`. Keep `standardNoteKinds` the union.
2. Remove now-redundant special cases: `packages/tylog_core/lib/src/enrich.dart:34` (`|| note.kind == 'project'`), `lib/widgets/work_surface.dart:745` (`|| note.kind == 'project'`). grep for other `== 'project'` checks that existed only because project was structural; leave module_pack `projects/<id>/` paths alone.
3. New project pages are created in `notes/` like other entities: drop the `'project' => 'projects'` arm in `lib/vault.dart` (~163) and `lib/workspace_controller.dart` (~944). Existing `projects/*.typ` files are not moved.
4. `NoteRef.partOf` (List<String>, default const []): ids or titles of parent entities. Scanner fills it from `properties["part_of"]` (Typst array of strings, or a single string) plus the legacy `project` field (appended if non-empty and not already present). Add to toJson/fromJson/copyWith. Bump `kVaultIndexVersion` with a changelog line in its doc comment.
5. Writer: `serializeNoteHeader` / `_typstDictionary` must emit a list value for `part_of` as a Typst array `("a", "b",)`. If `_typstDictionary` only supports strings, extend it for `List<String>`. Never add a new top-level `tylog.note` parameter (old vault `tylog.typ` copies would fail to compile).
6. Helper in tylog_core: `Map<String, List<NoteRef>> childrenByParent(Iterable<NoteRef> notes)` resolving each partOf entry by id, then by title/alias (case-insensitive); unresolved entries ignored.

## Tests (must fail before the change)
- scanner reads `part_of` list, single string, and legacy `project:` into `partOf`; no duplicates.
- header written with part_of compiles with typst/tylog/lib.typ (use the existing compile-test pattern; see memory: writers must compile, not parse).
- childrenByParent: a person with two parents appears under both; title and id resolution.
- `project` in entityNoteKinds, not structuralNoteKinds; existing tests that assumed otherwise updated.

## Done when
`cd packages/tylog_core && dart test` and `flutter test` (affected files at least: entity_kinds_test, work_surface, enrich, scanner tests) pass; `dart analyze` clean on touched files. Do not commit. Report changed files and test commands run with results.
