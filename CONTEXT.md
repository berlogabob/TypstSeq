# TyLog Knowledge Model

TyLog is a research logbook where notes, concepts, evidence, and arguments share one graph without losing the identity of external material or prior edits.

## Current status

Current release: 0.12.0+133 (2026-10-08). Tasks are typed lines with four
statuses, editable chips and shared rows; Doing runs the timer. Image blocks
support sizing, alignment, moves and crop. Journal lists pages with a collapsed
Agenda. Sync confirms uploads from listings and keeps local safety copies;
headerless daily repair keeps existing text.

## Open work

- Phone verification of 0.11.6–0.12.0: sync loss fixes, mention lookup, image blocks, crop, task typing with a phone keyboard, and headerless-daily repair.
- Android autocomplete jumping/revert remains undiagnosed. Suspects: a late IME full-text update or a post-sync reload.
- A headerless daily went three hours without syncing on the A24; cause unknown.
- Cap the revision envelope, which grows without bound.
- Database-error rollback in `lib/workspace_controller.dart` can delete a newly created note.
- EmbeddingGemma phone trial at 256 dimensions before switching models.
- Deferred: image captions/figure, text wrap and anchors; task session-history view; converting imported checklists to tasks; quick-add date parsing.
- `wip/incremental-index` is parked; the macOS app is still on an old build.

## Language

**Node**:
An addressable knowledge record with a stable identity and a type. Notes, concepts, claims, tasks, people, and works are node types.
_Avoid_: Page, block, graph mode

**Edge**:
An addressable typed relationship between two nodes. Its validity period describes the relationship, independently of when TyLog stored it.
_Avoid_: Link record, diagram line

**Source**:
External evidence with a stable identity, such as a document, book, article, recording, or dataset. Changes to its bytes create source versions without changing that identity.
_Avoid_: Attachment, note

**Revision**:
An immutable record of a change to an authoritative entity. Parent revisions express history and concurrency; wall-clock time does not choose a winner.
_Avoid_: Backup, autosave copy
