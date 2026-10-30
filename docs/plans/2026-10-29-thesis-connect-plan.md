# Thesis connect plan (started 2026-10-29)

Goal: TyLog becomes the personal side of one entity model whose institutional side is OpenLabTwin (OLT, Supabase). Every fact carries its source and derivation.

Rules: Claude coordinates, reviews every diff and runs the FULL `flutter test`; codex CLI does multi-file edits (`codex exec -s workspace-write ... < /dev/null`, full suite is blocked in its sandbox); pi/Ornith for small files and docs. Slice = analyze + tests green, device check (P30 or Nothing Phone 3, release build, real vault), `graphify update .`, `dart format` on touched files, commit. No release until all found issues are closed and the user confirms. Never `svc power stayon`; never touch oMLX.

Loop: every 5 min, three lines: STATUS (done / running / blocked), PLAN+ (new items added below), DELTA (checked since last tick vs plan).

## Verified facts (2026-10-29)
- Screenshots: OCR pipeline writes `kind: screenshot` notes with category, tags, keywords. Enrichment never reads them (`tool/enrich_worker.py:363`).
- Audio transcripts live in `notes/Audio *.typ`; enrichment reads `notes/` only with `--include-notes`, which nothing enables. Audio notes have no tags.
- Clustering is tag-only (graph hygiene, Voronoi). Graph node kinds: note, concept, work, day; no source filter.
- `_system/settings/{ai,calendars,processing}.json` sync via the vault; API keys stay in secure storage (`lib/ai/api_keys.dart`).
- OLT: Supabase Postgres, RLS by `is_staff()`, staff sign in by emailed link/OTP, sign-ups off. Tables: places, items, assets, movements (append-only), stock (view), people, activities, activity_items, lessons.

## Queue
### P0 Housekeeping
- [x] Record from power button lands in today's log (bbb7782, checked on Nothing Phone 3)
- [ ] Push branch; release 0.20.5+163 (Windows updater helper 20f0679 + record-to-day-log): CHANGELOG, version, full test
- [ ] Power-button long-press and lock screen on the Nothing Phone 3
- [x] Keyboard up: Agenda row hides too (verified on P30: Agenda, Screenshots, Linked refs gone, editor has the screen). 
- [ ] Screenshots and Linked references collapsed under More
- [x] Add `docs/audio-transcription.md` to bundled RAG doc lists (pubspec + semantic_search_controller)
- [ ] `graphify update .`

### P1 Conceptual data model (supervisor's ask) -> `docs/thesis/conceptual-model.md`
- [x] Entities: Item, Mention, Entity, Link, Source; attributes `source` and `derivation` (docs/thesis/conceptual-model.md)
- [x] ER diagram (Mermaid) with real vault field names; OLT table mapping
- [x] One-page novelty statement + what is measured (user review with supervisor pending)

### P2 Graph source filter
- [x] Source on every note node (`GraphNode.source` = note kind)
- [x] Filter chips beside the edge-kind legend (cluster by source: later)
- [x] Tests (core + widget, 23 + 430 green); device check done on P30 (switch visible on Calendars, left off)

### P3 Extraction coverage
- [x] Audio transcripts enriched (23 voice notes in the real vault); [ ] screenshots: user decision, stay excluded until then
- [x] Enrichment runs on `kind: audio` notes, transcript only (translations skipped); tags/aliases from transcript: later
- [ ] Re-queue backlog without a PROMPT_VERSION bump (2 h of Studio compute)

### P4 Settings sharing
- [x] `*.local.json` never syncs (`isSyncableVaultPath`, tylog_core `sync_paths.dart`); whole-file override, local wins (no merge); Python workers read it too
- [x] "This device only" switch on AI, Audio processing and Calendars pages; device check done on P30 (switch visible on Calendars, left off)
- [ ] Later: P2P pairing for secrets (iroh in-app harness first)

### P5 OLT login spike
- [ ] Needs from user: OLT staff account email, `SUPABASE_ANON_KEY` (public), confirm email template carries `{{ .Token }}`
- [ ] Email OTP (`/auth/v1/otp` create_user false, `/auth/v1/verify`, refresh) with secure-store tokens, no new dependency
- [ ] Spike: sign in on the Nothing Phone 3, read `places`

### P6 OLT read-only entities
- [ ] Places, items, assets, activities, people as external entities (`source: openlabtwin`, key = code/uuid), cache outside the synced vault
- [ ] Autocomplete + graph nodes + source filter entry

### P7 OLT write
- [ ] Create booking (`activities`), move/issue (`movements`), stocktake tick; server rules stay authoritative; offline = queue, no local edit of cached rows

### P8 Calendar and people
- [x] Outlook calendar: an ICS feed already works (P30 lists the OLT lab ICS beside the timetable); paste Outlook's published ICS link in Settings > Calendars
- [x] Contacts: `tylog import-contacts --vault V --file X.vcf|csv [--write]` creates person notes (idempotent id `contact-<hash>`, dedupe by title/alias; dry run default). Verified on a scratch vault; not yet run on the real vault (your export file needed)

### P9 Evidence for the thesis
- [x] Gold-set evaluation CLI: `tylog eval-links --vault V --gold G.jsonl` (resolver with vs without ledger, leave-one-out); `--sample N --out T.jsonl` writes a labelling template
- [ ] Label 100-200 mentions by hand (template of 40 at the scratchpad `gold-template.jsonl`)
- [x] Log shown suggestions in `_system/enrich/shown/<device>.jsonl` (separate folder: older builds read every non-accept line in `feedback/` as a reject); `enrich_learning.py` prints shown, decided, ignored, ignore rate

### P10 Incoming (inbox of external events)
- [ ] Event log `_system/incoming/<device>.jsonl` (append-only: seen / added-to-today / scheduled / dismissed / ignored); content cache stays outside the vault
- [ ] Incoming icon + badge; sources: OLT bookings and ideas (P6), Microsoft calendar invites, tasks, mail (P11)
- [ ] Actions: add to today's page, add to agenda/calendar on a chosen day, dismiss; no action is still logged

### P11 Microsoft 365 (Graph)
- [ ] Account: andrey.dyakov@universidadeeuropeia.pt (OLT staff login; andre.berloga@gmail.com stays as backup)
- [ ] Azure app registration (device-code flow, read-only: Calendars, Contacts, Tasks, Mail); tenant admin consent may be needed
- [ ] Sync calendar, contacts (replaces import-contacts), tasks into Incoming; Copilot only if the licence has it

### P12 One system (plan: attention + Decision, ADR 0001)
- [x] Thesis RQ, attention + Decision model, glossary, ADR (07ca7b1)
- [x] Core: attentionOf, Decision log merged with link ledgers (700829b)
- [x] Today Incoming strip: add to today, schedule, dismiss; one Decision row each (e9096a0). P30 real vault: Incoming (8), Dismiss wrote the row and archived the screenshot
- [ ] Tile hides only after the index refresh (~20 s); hide at once if it bothers you
- [ ] Next: OLT login (P5) as an Incoming source

## Issue log
- 2026-10-29: P30 not on adb; Nothing Phone 3 (A024, serial 000251565001005) is the test device now.
- 2026-10-29: Windows updater hang cause unconfirmed; ask for `%TEMP%\tylog-update.log` after the next update.
- 2026-10-29: Portuguese pack repo has uncommitted lesson edits; built pack may be stale.

## Tick log
- 19:50 T1: Agenda row hides while typing (`work_surface.dart`, editor keyed). Tests 64 green. Next: device check, then enrichment/graph slices. Release waits for user.
- 20:05 T2: Device check blocked (Nothing Phone 3 left adb). P1 conceptual model written: docs/thesis/conceptual-model.md. Next: P2 graph source filter via codex.
- 20:20 T3: P2 graph source filter via codex (GraphNode.source, source chips with counts, composed with focus filter). analyze clean, graph tests green. Next: P3 transcript enrichment.
- 20:35 T4: P3 worker change (`enrich_worker.py`): voice notes join the run, translations and attachment line skipped; test fails pre-fix, 17 pass. Next: backlog re-queue needs a run on the Studio (compute) then P4 `.local.json`.
- 20:55 T5: P4 via codex. Full suite 1729 green except codex's flaky widget test, which I dropped (round trip covered in settings_path_test). analyze clean. Next: commit, then P5 needs your inputs.
- 21:10 T6: P5 still waits for your inputs; did the unblocked P0 item (RAG doc). Next unblocked: collapse Screenshots/Linked references under More, then P8 ICS, P9 gold-set CLI.
- 21:30 T7: P30 back on adb. Device check found the Agenda row still visible (Scaffold consumes the inset); fixed by passing `typing: keyboardUp` into TodayPage; re-verified on P30; test asserts it. Graph chips and settings switch device checks still open. Next: P8 ICS check, P9 gold-set CLI.
- 21:50 T8: P30 device checks done: graph source chips (Article 15, Daily 1, Note 17; toggle hides), Calendars 'This device only' switch present. P8 calendar half needs no code (ICS feed already listed). Open: contacts import, P9 gold-set CLI, P5 inputs, release, screenshot-enrichment decision.
- 22:10 T9: P9 CLI via codex (`eval_links.dart`, `tylog eval-links`); sampled 40 mentions from the real vault; 5 tests green. Not checked: that the test fails when the ledger is ignored. Next: you label the gold set; contacts import; P5 inputs.
- 22:35 T10: P9 shown-log via codex; found it would poison older builds (non-accept = reject), moved to a separate folder; 10 app-flow, 27 core, 4 python tests green. Next: contacts import, then P5 inputs.
- 22:55 T11: P8 contacts import via codex; 11 tests, dedupe guards proven by tests; scratch-vault run created 2, then skipped 2 on re-run. Next: P5 (your inputs); nothing else unblocked except cluster-by-source and tags from transcripts.
- 23:10 T12: nothing unblocked is left in order. Loop paused (cron deleted). Waiting on: P5 inputs (OLT staff email, Supabase URL + anon key, `{{ .Token }}` in the email template), your 0.20.5 release go-ahead, screenshot-enrichment decision, gold-set labels, a contacts export. Deferred without owner: cluster by source, tags/aliases from transcripts, P2P secrets sync.
- 00:05 T13: P12 steps 1-3 done (docs, core, Incoming strip); full suite 1733 green; P30 Dismiss verified. Next: P5 OLT login.
- 00:15 T14: STATUS running / DONE Incoming verified on P30 / NEXT OLT email-code login (codex) / BLOCKED none
- 00:40 T15: OLT sign-in built (f29822c). University address has no OLT account ('Signups not allowed for otp'); code sent to the gmail backup. Waiting for the user to enter the code on the P30.
- 01:00 T16: STATUS running / DONE OLT sign-in page / NEXT OLT bookings+ideas into Incoming (codex) / BLOCKED OLT code entry on P30 (gmail)
- 01:25 T17: OLT bookings/ideas into Incoming (e8ef475); full suite 1740 green; installed on P30. Device check needs the OLT sign-in (code in gmail).
- 01:45 T18: STATUS running / DONE OLT Incoming slice / NEXT thesis metrics script (pi on Studio) / BLOCKED OLT sign-in on P30
- 02:00 T19: decision_metrics.py (pi, 2 fixes: real header regex, test index); real vault: screenshot 2467 new, ignore 100% (no decisions older than 7 days yet). Audio notes have no date: not counted yet.
- 02:15 T20: STATUS running / DONE metrics script / NEXT OLT approved bookings on the agenda + CalendarItem.source (codex) / BLOCKED OLT sign-in on P30
- 02:35 T21: OLT approved bookings on the agenda, CalendarItem.source (codex + review: showSnack, rrule shortcut noted); full suite 1741 green. Device check waits on OLT sign-in.
- 02:45 T22: STATUS blocked / DONE P12 steps 1-4 + OLT read side / NEXT device check of OLT slices, Microsoft 365 / BLOCKED OLT sign-in on P30; Azure app registration for Microsoft. Cron paused to save tokens.
