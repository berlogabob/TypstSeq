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
  meta-line: "Prepared 2026-11-17 · repo facts checked 2026-11-17 · live OLT counts pending (see Gaps)",
  standfirst: [Both halves of the system work on their own, but the link between them is not finished. TyLog extracts, resolves and learns from decisions. OpenLabTwin holds rooms, bookings and storage in one append-only log. Two things block the thesis evidence on the storage side. Its office screens are too hard to use, so no shelf has been counted yet. And loans written in TyLog never reach OpenLabTwin. Wave 36 fixes both, in that order. Most of the supervisor's suggested architecture is already in place by other means. We adopt three points, adapt four and decline two (see Supervisor suggestions).],
)

#kpi-row((
  ("0 / 28", "Places counted", "per the 2026-09-27 import; live check pending"),
  ("9 taps", "Hand out one unit", "today's office, from the code"),
  ("0", "TyLog loans in OLT", "bridge not built yet"),
  ("38", "Sources found", "literature step, 2026-11"),
))

= Research question

In a personal knowledge system fed by human, machine and institutional sources, does one provenance-aware Item model with one Decision log (accept, defer, dismiss, ignore) make sources linkable and attention measurable? And does the system improve from those decisions over time, compared with per-source silos? The framing is mixed-initiative interaction (Horvitz 1999), with the lab's places and equipment as boundary objects (Star and Griesemer 1989). Supporting work found in the literature step: fragmentation across tools (Bergman et al. 2006), and inventory record inaccuracy coming from unrecorded movements (DeHoratius and Raman 2008).

= System map

#data-table(
  ("Mode", "Who uses it", "What it does", "Store"),
  (
    ("OpenLabTwin alone", "Lab staff, students (public forms)", "Bookings, schedule, TV, storage: places, tagged units, stock, loans, stocktake", "Supabase Postgres, append-only movements"),
    ("TyLog alone", "One person, phone and desktop", "Day notes, voice, screenshots, articles; an LLM extracts mentions, a deterministic resolver links them, decisions are logged", "Typst files in a synced vault + local index"),
    ("Together", "The lab technician", "Equipment and places exported into the vault; a loan written in a day note becomes a loan task, then an OLT movement (Wave 36)", "OLT stays the record; TyLog is an input channel"),
  ),
  widths: (2.6cm, 3.2cm, 1fr, 3.6cm),
  right-from: none,
)

= What is built

#scorecard((
  ("Enrichment layer", "Met", "ok", "LLM as a stateless mention extractor; resolver + feedback ledger in the app; backfill 995/995 days, 2519/2519 screenshots (recorded 2026-10-31)"),
  ("Decision log", "Met", "ok", "One row per decision across Incoming and link review (ADR 0001); knowledge states with proposed_by and confidence (ADR 0002)"),
  ("Sources in one graph", "Met", "ok", "Typed text, OCR, ASR, articles, calendar (ICS), OLT bookings; graph filters by source"),
  ("Natural-language loans", "Met", "ok", "Wave 34: a sentence becomes a loan task linked to equipment notes; double-loan warning; usage hours"),
  ("OLT storage database", "Met", "ok", "Place codes, tagged units, stock as a view over movements, Needs attention, nightly mirror (live since 2026-09-27)"),
  ("OLT office for storage", "Not usable", "bad", "Generic movement dialog in database verbs; 9 taps to hand out one unit (see Gaps)"),
  ("Real storage data", "Not started", "warn", "Every place still uncounted; the numbers are the old spreadsheet import"),
  ("TyLog → OLT loans", "Not started", "warn", "Loan tasks stay in TyLog; Wave 36 bridge"),
  ("Gold set", "Pending (user)", "warn", "Evaluation CLI ready (eval-links, loan_eval); 0 of 100-200 mentions labelled"),
))

= Gaps found on 2026-11-17

- *Office effort.* From the widget code: finding a tagged unit takes 2 taps with the camera, handing one out 9, taking it back 8, moving 5 units 9, and counting a shelf 7 (6 with its QR label). Handing out, taking back and moving all make staff pick a database verb (issue, return, move).
- *Untrusted numbers.* The 2026-09-27 import left all 28 coded places uncounted, on purpose. It holds 140 items and 83 tagged units. No count has happened since, so stock still reflects the old spreadsheet.
- *Two identities for equipment in TyLog.* One comes from the vault export (asset tag), the other from a live per-device connector (database id). Fixed by ADR 0003: the export is the only path.
- *Live check blocked.* The Mac's OLT settings point at the project paused on 2026-10-21. The read-only snapshot script is ready and runs once the settings are updated.

= Supervisor suggestions: our answer

The note is read as suggestions. Where we already meet a point by other means, we say so.

#data-table(
  ("Suggestion", "Answer", "How / why"),
  (
    ("LLM proposes, never writes", "Adopt (already)", "Worker writes only sidecar JSON; the app resolves and the user confirms"),
    ("Fact metadata: source, confidence, status, provenance", "Adopt (already)", "ADR 0002 states + proposed_by + confidence; PROV-O terms used in the write-up (W3C 2013)"),
    ("Human approval for ontology changes", "Adopt (already)", "Vocabulary changes are proposals in Incoming"),
    ("Seven statuses (extracted … obsolete)", "Adapt", "Mapped onto our five; contested = OLT refused or sources disagree (Wikidata ranks as precedent)"),
    ("Typed command registry, slash commands", "Adapt", "/loan out and /loan return parsed without an LLM; same review card (Shin et al. 2021: constrained sublanguage)"),
    ("Business rules, permissions", "Adapt", "In Postgres: RLS for staff, a trigger refuses a second loan of a unit; one rule for every channel"),
    ("Transaction with preview, audit, events", "Adapt", "Review card = preview; tap = confirm; append-only movements + audit trigger = trail"),
    ("Graph DB (Neo4j / Jena / GraphDB) + OWL", "Decline for now", "A graph is a data model, not a product (Angles and Gutierrez 2008); a file index + Postgres is enough at one-lab scale; revisit if a query needs it"),
    ("Vector DB, queues, many services", "Decline for now", "The note itself allows a smaller first version; semantic search already exists in TyLog"),
  ),
  widths: (5cm, 2.6cm, 1fr),
  right-from: none,
)

= Decisions (Wave 36)

#fact("D1 Loans record", [OLT movements are the only record; TyLog is an input channel; each movement notes its source.])
#fact("D2 Identity", [Asset tag and place code, through the vault export only (ADR 0003).])
#fact("D3 Double loan", [A database trigger refuses a second loan of the same unit, for every channel.])
#fact("D4 Unknown borrower", [Skipped and listed; staff add the person; no automatic person rows.])
#fact("D5 Office", [Rebuilt around jobs (find, hand out, take back, move, count); same schema.])
#fact("D6 Typed lines", [/loan out ... and /loan return ... in TyLog, no LLM; a baseline against the LLM path.])
#fact("D7 Graph", [No graph server. An ontology and SHACL export only if the supervisor confirms.])

= What will be measured

#data-table(
  ("Metric", "Source", "State"),
  (
    ("Accept rate of suggested links over time", "enrich_learning.py, decision ledger", "Running"),
    ("Ignore rate and decision latency per source", "decision_metrics.py", "Running"),
    ("Resolver precision/recall, with vs without the ledger", "tylog eval-links + gold set", "Waiting for labels"),
    ("Taps and seconds per job: old office, new office, /loan line, sentence", "W36.7 baseline, W36.27", "Baseline done"),
    ("Share of places counted; spreadsheet vs counted difference", "storage_snapshot.py", "Script ready"),
    ("Channel mix and refusal rate of loans", "Movement notes, nightly jsonl", "After the bridge"),
  ),
  widths: (1fr, 5cm, 3cm),
  right-from: none,
)

= Plan and what is needed

#scorecard((
  ("Phase 0: status, research, ADRs", "In progress", "info", "Snapshot script, literature (38 sources), ADR 0003 done"),
  ("Phase 1: office works alone", "In progress", "info", "Double-loan rule written; job screens next"),
  ("Phase 2: real data", "Pending (user)", "warn", "Shelf list confirmed, labels printed, R15 and the Vitrine counted"),
  ("Phase 3: together with TyLog", "In progress", "info", "Per-loan export; then bridge, typed /loan lines"),
  ("Phase 4: evidence", "Not started", "neutral", "Nightly metrics, effort table, gold set, status v2"),
))

#callout(title: "Questions for the supervisor", tone: "info")[
  1. Is the answer to the suggestions acceptable, in particular no graph server for now?
  2. Should the Godot twin and the demand forecast stay in scope, or is the movement log plus the TyLog graph enough for the institutional side?
  3. Is a 100-200 mention gold set plus the effort table enough evidence for the improvement claim?
]
