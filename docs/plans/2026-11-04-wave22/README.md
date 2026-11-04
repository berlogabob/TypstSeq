# Wave 22 (user OK 2026-11-04). One codex run per item, in this order. Each: read the code first, reuse
# existing primitives (entities/part_of, boards, mounts, connectors, Incoming + decision ledger), surgical
# note writes only, writer output must compile, tests must fail before the fix. No new dependencies.

## S3 Duplicate finder + merge
Settings/maintenance action "Duplicates": groups entity/note pages with the same enrichKey of title/alias, or same email
link. Merge = pick survivor; move aliases + part_of + body (appended under a heading) into it; repoint every
`#tylog.ref-note(...)` / link to the loser across the vault (surgical, per file); delete loser; one decision-ledger entry.
Preview before writing. Real cases: notes/AndreSabino.typ + "notes/André Sabino.typ"; IADE x3.

## S2 Namespace -> structure
Check lib/namespace_migration.dart (P1 task g). Expose it as a one-tap action on any page whose title has `/`
(and a bulk action in Settings): create missing parents, set part_of, keep full path as alias. Idempotent.

## S8 Pack update check
Packs installed with a GitHub source (`_system/modules/<id>.json`): check latest release at most weekly
(and on Extensions open), show "Update to X" button in Extensions; install via existing pack install path.
Offline/rate-limit = silent.

## S4 Person timeline
On an entity page (any kind), a "Timeline" section: every note that links it (backlinks) + tasks + audio
(From link) + screenshots, grouped by day, newest first, lazy paged (20 per page). Uses the index only.

## S5 Audio -> task/agenda proposals
Worker (tool/transcribe_worker.py context stage): also extract action items and dates from the transcript into the
sidecar + `_system/enrich/...` style proposals; app shows them in Incoming as "Add task" / "Add to agenda" chips,
accept writes a task line into the audio note (linked to the From person if present), reject goes to the ledger.

## S6 GitHub issue sync per board
Board setting "Sync with GitHub repo owner/name" (signed-in device flow token). Open issues appear as cards in
the columns view (todo/doing via label `doing`, done = closed). Moving a card to done closes the issue; out of done
reopens. Pull on open + manual refresh; conflicts: GitHub wins, shown in the decision ledger.

## S7 OLT rooms + stock on the whiteboard
Whiteboard "Add from OpenLabTwin": places tree (part_of) as tree layout; asset cards show stock level badge
(low = warning color) from the connector cache. Read-only.

## S1 One review queue
Incoming gets typed sections from a small registry: enrich mentions (exists), audio proposals (S5), OCR rows
(future: rows.jsonl with review:true from tylog-form-ocr dataset mounts), OLT pending bookings (read-only info).
Same accept/reject → decision ledger. Keep 7-days paging.

## S3a Duplicate finder (read-only)
Core function `findDuplicates(VaultIndex)` -> groups of NoteRefs (entity kinds + kind note) sharing an enrichKey of
title/alias (packages/tylog_core/lib/src/enrich.dart enrichKey). Settings > Maintenance "Duplicates" lists groups with
backlink counts. No writes. Unit test with AndreSabino / "André Sabino" and IADE x3 shapes.

## S3b Merge two pages (reuse rename)
From a duplicate group: choose survivor + loser. Reuse the existing rename/link-repoint code path (find it: the
code that updates references when a page is renamed) to repoint every reference to the loser's id/title/aliases to
the survivor. Survivor header: union aliases (+ loser title), union part_of (surgical header writers). Loser body
appended to survivor under `== Merged from <title>` unless empty. Then delete loser. One decision-ledger line.
Preview dialog lists files to change before writing. Tests: refs repointed, compile, nothing lost.

## S9 Mention chooser (user, A24 2026-11-04)
Today tapping a "?" mention chip in Incoming / daily review accepts the top guess at once; × only rejects it; there
is no way to pick the right person. Change lib/widgets/enrich_review.dart + callers: tap on a review chip opens a
sheet "Who is <surface>?" with: the line of text it came from (so context like "my boss" is visible), all ranked
candidates (title, kind icon, part_of parents, last-seen day), "Other page…" (search over entity + note pages),
"New page", "Not a person/ignore". Choosing calls the existing onAccept(mention, chosen) (ledger learns the
surface -> entity); others implicitly not rejected. Linked chips keep current behaviour. Widget test: choose the
second candidate -> onAccept gets it; Other page search -> onAccept gets that page.
