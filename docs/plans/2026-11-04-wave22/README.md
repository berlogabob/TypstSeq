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
