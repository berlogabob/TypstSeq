# TyLog big update: modular HMI (entities, boards, extension vaults, connectors, form OCR)

## Context
Thesis needs a modular human-machine interface: many sources (personal notes, Telegram bots, OpenLabTwin, courses, paper archive) on one entity model with one decision log. Today TyLog has none of the shared primitives this needs:
- `project` is a structural kind (`packages/tylog_core/lib/src/models.dart:475`), own folder `projects/`, single `project:` field; no `part_of` relation anywhere; icons hardcoded (`lib/widgets/constants.dart:149` + duplicate `lib/knowledge_screen.dart:635`).
- One vault open at a time (`lib/vault_registry.dart`); no mounts; `VaultStorage` is abstract (`packages/tylog_core/lib/src/storage.dart:40`) but sync is Nextcloud-only (`lib/nextcloud_sync.dart`).
- Module packs install by file only, no version compare, no update source (`module_pack.dart:175`, manifest `additionalProperties:false`). PT course lives in `github.com/berlogabob/tylog-pack-pt-pt`, no releases.
- Graph = InteractiveViewer + CustomPaint (`lib/graph.dart:494`), positions not persisted; no board/kanban code.
- Tasks: statuses todo/doing/done/cancelled, all moves via `applyTaskStatus` (`scanner/task_mutation.dart:46`).
- OLT: `lib/olt/` reads activities/ideas/places (id,name,kind only). OLT `places` already has `parent_id` + hierarchical `code`.
- Bot architecture (Amadora-News-Bot `docs/2026-10-31-architecture-tylog-brain.md`): one vault/space per bot, bot writes only `_system/`, topic packs shared. Bot code freeze still on.
- GitDoIt (`~/Documents/GitHub/flutter-github-issues-todo`): reusable device-flow OAuth (`oauth_service.dart`), GitHub REST/GraphQL client, kanban drag-drop (`project_board_screen.dart:474-527`, DragTarget + LongPressDraggable). No git push/pull.

## Five primitives, everything else is a consumer
1. **Entity + relations.** Every non-structural note is an entity; kind is free text; kind registry `_system/settings/kinds.json` gives icon/label. Relation `part_of` (many parents) in `properties.part_of` (no new Typst header param, old `tylog.typ` keeps compiling). Legacy `project:` read as a `part_of` edge. Children computed in the index.
2. **Board.** One file per board, `boards/<id>.board.json` (syncs like notes). Cards: note/entity id, task id, asset (image copied to `assets/`), URL, text. Each board has a layout: `free` (whiteboard, x/y/size, frames, arrows), `columns` (kanban, columns bound to a field: task status, a property, or kind), `tree` (auto layout over `part_of`, heritage/database tree). Same file, three views.
3. **Mount (extension vault).** Read-only `VaultStorage` mounted under `ext/<id>/`, indexed with the main vault, links by id work across. Transports: local folder, GitHub (pull via API zip of release/branch; push edits back via GitHub contents API commit for repos you own, conflict = keep both + review). Packs become a mount kind with update check (manifest gains `update: {github: owner/repo}`, version compare). Telegram bot vaults = mounts.
4. **Connector.** One interface `{refresh(), items(), entities(), decide()}` for external live sources: OLT (expand to places tree with `parent_id`/code, items, assets, stock), ICS calendars, GitHub issues/Projects v2 (from GitDoIt). External entities read-only (thesis rule 1); decisions go to the single ledger.
5. **Review queue.** Existing Incoming + decision log (`_system/decisions/*.jsonl`) is the one human-in-the-loop surface for every module: enrich mentions, OCR rows, bot drafts, OLT bookings.

## Phases
**P1 Entities + kanban (ship first)**
- Move `project` to `entityNoteKinds`; drop special cases (`enrich.dart:34`, `work_surface.dart:745`); new projects → `notes/`; existing `projects/*.typ` untouched; module packs keep `projects/<id>/`.
- Kind registry + icon picker (~30 Material icons) in New entity dialog; `iconForKind`/`labelForKind` read registry; delete duplicate switch.
- Scanner: `NoteRef.partOf` from `properties.part_of` + `project:`; bump `kVaultIndexVersion`.
- Entity page: "Part of" chips (add/remove, surgical `replaceNoteHeader`) + "Contains" grouped by kind. Magic "Project" → "Part of…".
- Knowledge list as tree (multi-parent node under each parent).
- Kanban: `columns` view over tasks where `task.project`/note `part_of` ∋ entity; columns todo/doing/done (+ cancelled hidden filter). Drag = `applyTaskStatus`; warn that Doing stops other clocks. Drag-drop lifted from GitDoIt `project_board_screen.dart:474-527`. Board file format v1 written here (columns layout only).
- Logseq namespace titles (`A/B/C`) → parent pages + `part_of`, full path kept as alias.
- Issue lines (Task H): `@TyLog @fixit text` = issue card on the TyLog kanban; GitHub issue sync in P2 (send = a Decision, number written back, closed<->done).

**P2 Mounts + GitHub** — mount registry per vault (`_system/settings/mounts.json`, tokens in secure storage); local-folder mount; GitHub pull (zip); pack update channel; GitHub push (contents API, own repos); device-flow OAuth from GitDoIt. First user: PT course repo.

**P3 Whiteboard** — `free` layout on InteractiveViewer (reuse graph pan/zoom), drop anything (note, entity, task, image, link, text), frames, arrows; `tree` layout over `part_of`.

**P4 Connectors** — Connector interface; OLT expanded (places tree → place entities with `part_of`, items/assets/stock as read-only entities); GitHub issues/Projects v2 as tasks on boards.

**P5 Paper-archive form OCR (separate repo, reusable)** — Python on Studio (Mac never overloaded): template = blank scan + field boxes JSON; align filled photo to template (OpenCV ORB + homography), crop fields, handwriting OCR per field via Studio vision model, confidence; output dataset container (JSONL + crops + manifest, packaged as a mount/pack). Low-confidence rows → review queue. Accepted rows link to OLT people/places/items, archive, atlases, storage trends, Idea hub.

**P6 Telegram bot vaults** — bot vault mounted read-only; waits on the bot code freeze and the open questions in the architecture doc.

## Execution mode (user: maximize codex, Claude save mode)
- Claude: design, task specs, review, verification only. Codex (`codex exec ... < /dev/null -s workspace-write`) does each implementation task from a written spec; mechanical edits to haiku subagents; Ornith 35b on Studio for bulk/cheap text. Short 30-min status cron with cheap model.
- Each P1 task = one codex run with a spec file in `docs/plans/2026-11-03-entities-boards/`: (a) kinds move + special cases, (b) kind registry + icons, (c) part_of scanner + index bump, (d) entity page Part of/Contains, (e) knowledge tree, (f) kanban board, (g) namespace migration. Claude reviews each diff before the next.
- No deploy until P1 ends; release only when all found issues are fixed.

## Verification (P1)
- Unit: scanner reads `part_of` list + legacy `project:`; header writer output compiles with the vault's `tylog.typ` (test must fail before the fix); kind registry icons; kanban drop calls `applyTaskStatus`.
- Index rebuild on a copy of the real vault: IADE shows children; a person with two parents appears under both; namespace titles become trees.
- macOS via /verify: build Universidade Europeia > IADE > center > lab, put a professor in a lab + UNIDCOM, open a project kanban and move a task.
- Phase end: P30 release-signed profile build on the real vault + Nextcloud.
- `graphify update .` after code changes.
