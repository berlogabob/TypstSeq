// Thesis status, 2026-11-17. Compile: typst compile 2026-11-17-status.typ
#import "lib.typ": *

#show: report.with((
  title: "Thesis status: one model, many sources",
  author: ("Andrew Diakov",),
  footer: "Thesis status · 17 Nov 2026",
  lang: "en",
))

#title-block(
  "Thesis status: one model, many sources",
  subtitle: "TyLog (personal) + OpenLabTwin (institutional) · Wave 36",
  meta-line: "17 Nov 2026 · rechecked against code, config and the live lab database the same day",
  standfirst: [Both halves of the system work on their own, and the link between them is now built but not yet switched on. TyLog extracts, resolves and learns from decisions. OpenLabTwin keeps rooms and bookings in tables, and storage as an append-only log of movements. Wave 36 rebuilt the office around staff jobs, put a database rule against double loans live, and built the TyLog-to-lab loan bridge. What blocks the evidence now is real data: no shelf has been counted yet, and the bridge has not been applied to real loans. Most of the supervisor's suggested architecture is already in place by other means. We adopt three points, adapt five and decline one (see Supervisor suggestions).],
)

#kpi-row((
  ("0 / 28", "Places counted", "live database, 2026-11-17"),
  ("9 → 4", "Taps to hand out a unit", "old office vs new, from the unit page"),
  ("139", "Database tests passing", "pgTAP on the live project"),
  ("38", "Sources found", "literature step, 2026-11"),
))

= Research question

In a personal knowledge system fed by human, machine and institutional sources, does one provenance-aware Item model with one Decision log (accept, defer, dismiss, ignore) make sources linkable and attention measurable? And does the system improve from those decisions over time, compared with per-source silos? The framing is mixed-initiative interaction (Horvitz 1999), with the lab's places and equipment as boundary objects (Star and Griesemer 1989). Supporting work found in the literature step: fragmentation across tools (Bergman et al. 2006), and inventory record inaccuracy coming from unrecorded movements (DeHoratius and Raman 2008).

= System map

#data-table(
  ("Mode", "Who uses it", "What it does", "Store"),
  (
    ("OpenLabTwin alone", "Lab staff, students (public forms)", "Bookings, schedule, TV, idea hub, paper archive, storage: places, tagged units, stock, loans, stocktake", "Supabase PostgreSQL; storage as append-only movements"),
    ("TyLog alone", "One person, phone and desktop", "Day notes, voice, screenshots, articles; an LLM extracts mentions from notes, voice and screenshots, a deterministic resolver links them, decisions are logged", "Typst files in a synced vault + local index (JSON file and SQLite with vectors)"),
    ("Together", "The lab technician", "Places, units and professors exported into the vault; a loan written in a day note or a /loan line becomes a loan task, then a lab movement", "The lab stays the record; TyLog is an input channel"),
  ),
  widths: (2.6cm, 3.2cm, 1fr, 3.6cm),
  right-from: none,
)

= What is built

#scorecard((
  ("Enrichment layer", "Met", "ok", "The LLM returns mentions, keywords and loan proposals as JSON for day notes, voice notes and screenshots (never articles); the resolver links exact matches by itself (logged as auto) and sends the rest to review; backfill 995/995 days, 2519/2519 screenshots (2026-10-31)"),
  ("Decision log", "Met differently", "ok", "Two append-only ledgers per device: Incoming decisions (ADR 0001) and link review with proposed_by (ADR 0002). Not one log yet"),
  ("Sources in one vault", "Met", "ok", "Typed text, screenshot OCR, voice transcripts, articles, calendar feeds (ICS); the graph can hide or show each source; lab bookings and ideas arrive in Incoming"),
  ("Natural-language and typed loans", "Met", "ok", "A sentence or a /loan line becomes a loan task linked to a unit note; warning when the unit is already out; usage hours per unit"),
  ("OLT storage database", "Met", "ok", "Place codes, tagged units, stock as a view over movements, Needs attention, double-loan trigger (live 2026-11-17), nightly backup and mirror"),
  ("OLT office for storage", "Built, not deployed", "warn", "Rebuilt around five jobs; hand out 4 taps from the unit page, take back 2 (was 9 and 8); browser tests pass on live; phone try and merge to main pending"),
  ("Real storage data", "Not started", "warn", "0 of 28 places counted; 209 of 210 movements are the 2026-09-27 import receive, 1 is a consume"),
  ("TyLog → OLT loans", "Built, not applied", "warn", "Export (111 notes, dry run on live data), bridge and results chip built and tested; not applied or scheduled"),
  ("Gold set", "Pending (user)", "warn", "Evaluation CLI ready (eval-links, loan_eval); labels not started (40-line template ready)"),
))

= Gaps, and what changed on 2026-11-17

- *Office effort.* Before: handing out a unit took 9 taps, taking it back 8, moving 5 units 9 and counting a shelf 6–7, each through a database verb (issue, return, move). After the rebuild, measured in the browser from the screen where the job starts: hand out 4, take back 2, move 5 units 5, count a shelf with its QR 3, find a unit 3. No database verb is left. Human seconds come from the phone try.
- *Untrusted numbers.* The live database holds 28 places (none counted), 140 items, 83 tagged units (82 ok, 1 broken), 210 movements (209 import receives, 1 consume), no open loans and 20 possible duplicates. Stock still reflects the old spreadsheet until the shelves are counted.
- *Two identities for equipment in TyLog.* One came from the vault export (asset tag), the other from a live per-device connector (database id). Fixed: ADR 0003 makes the export the only path, and the connector now brings only bookings and ideas.
- *Not switched on yet.* The export and the bridge have not been applied to real data. The 30-minute schedule waits for a rebuilt `tylog` binary and a week of manual runs.

= Supervisor suggestions: our answer

The note is read as suggestions. Where we already meet a point by other means, we say so.

#data-table(
  ("Suggestion", "Answer", "How / why"),
  (
    ("LLM proposes, never writes", "Adopt (already)", "The enrichment worker writes only sidecar JSON. The app resolves it: exact matches are linked automatically and recorded as auto, and the rest wait for the user"),
    ("Fact metadata: source, confidence, status, provenance", "Adopt (already)", "ADR 0002 states; link decisions record proposed_by and, when known, confidence; PROV-O terms used in the write-up (W3C 2013)"),
    ("Human approval for ontology changes", "Adopt (already)", "Topic-cluster merges, splits and renames are proposals in Incoming; tags and kinds change only by the user's own edit"),
    ("Seven statuses (extracted … obsolete)", "Adapt", "Mapped onto our five. We have no contested state; the nearest is a lab refusal shown in Incoming (Wikidata ranks as precedent)"),
    ("Typed command registry, slash commands", "Adapt", "/loan out and /loan return parsed without an LLM; same review card (Shin et al. 2021: constrained sublanguage)"),
    ("Business rules, permissions", "Adapt", "In Postgres: RLS for staff, a trigger refuses a second loan of a unit; one rule for every channel"),
    ("Transaction with preview, audit, events", "Adapt", "Review card = preview; tap = confirm; staff can only add movements (fixes are adjustment rows); audit trigger on staff-edited tables; scheduled jobs instead of events"),
    ("Graph DB (Neo4j / Jena / GraphDB) + OWL", "Decline for now", "A graph is a data model, not a product (Angles and Gutierrez 2008); a file index + Postgres is enough at one-lab scale; revisit if a query needs it"),
    ("Vector DB, queues, many services", "Adapt", "No vector server: vectors live in TyLog's SQLite index (hybrid search with chunk citations) and in the lab's PostgreSQL (pgvector, idea matches). No queue; the note allows a smaller first version"),
  ),
  widths: (5cm, 2.6cm, 1fr),
  right-from: none,
)

= Decisions (Wave 36)

#fact("D1 Loans record", [OLT movements are the only record; TyLog is an input channel; a bridge movement carries the key `tylog:<task>:<tag>:out|return`.])
#fact("D2 Identity", [Asset tag and place code, through the vault export only (ADR 0003).])
#fact("D3 Double loan", [A database trigger refuses a second loan of the same tagged unit, for every channel (live since 2026-11-17).])
#fact("D4 Unknown borrower", [Skipped and listed; staff add the person; no automatic person rows.])
#fact("D5 Office", [Rebuilt around jobs (find, hand out, take back, move, count); same schema.])
#fact("D6 Typed lines", [/loan out ... and /loan return ... in TyLog, no LLM; a baseline against the LLM path.])
#fact("D7 Graph", [No graph server. An ontology and SHACL export only if the supervisor confirms.])

= What will be measured

#data-table(
  ("Metric", "Source", "State"),
  (
    ("Accept rate of suggested links over time", "enrich_learning.py, link-review ledger", "Script, run on demand"),
    ("Ignore rate and decision latency per source", "decision_metrics.py, Incoming ledger", "Script, run on demand"),
    ("Resolver precision/recall, with vs without the ledger", "tylog eval-links + gold set", "Waiting for labels"),
    ("Taps and seconds per job: old office, new office, /loan line, sentence", "W36.7, W36.14, W36.27", "Taps done; seconds pending"),
    ("Share of places counted; spreadsheet vs counted difference", "storage_snapshot.py", "First live run done"),
    ("Channel mix, loan duration and refusals", "Snapshot by note prefix, results log; nightly cron", "Code ready; cron not installed yet"),
  ),
  widths: (1fr, 5cm, 3cm),
  right-from: none,
)

= Plan and what is needed

#scorecard((
  ("Phase 0: status, research, ADRs", "Met", "ok", "Live snapshot, literature (38 sources), ADRs 0053 and 0003"),
  ("Phase 1: office works alone", "Built, not deployed", "info", "Double-loan rule live; job screens built and browser-tested; phone try and merge to main pending (user)"),
  ("Phase 2: real data", "Pending (user)", "warn", "Shelf list confirmed, labels printed, R15 and the Vitrine counted"),
  ("Phase 3: together with TyLog", "Built, not applied", "info", "Connector cut to bookings and ideas, /loan lines, loans JSONL, bridge, results chip; apply and schedule pending"),
  ("Phase 4: evidence", "In progress", "info", "Snapshot metrics code done; effort table, gold set and status v2 pending"),
))

#callout(title: "Questions for the supervisor", tone: "info")[
  1. Is the answer to the suggestions acceptable, in particular no graph server for now?
  2. Should the Godot twin and the demand forecast stay in scope, or is the movement log plus the TyLog graph enough for the institutional side?
  3. Is a 100-200 mention gold set plus the effort table enough evidence for the improvement claim?
]
