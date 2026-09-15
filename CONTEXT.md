# TyLog Knowledge Model

TyLog is a research logbook where notes, concepts, evidence, and arguments share one graph without losing the identity of external material or prior edits.

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
