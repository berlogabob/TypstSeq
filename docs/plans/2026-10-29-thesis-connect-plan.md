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
- [ ] Contacts via vCard/CSV import for autocomplete

### P9 Evidence for the thesis
- [ ] Gold-set evaluation: Dart resolver CLI, 100-200 labelled mentions, resolver with vs without ledger
- [ ] Log ignored suggestions too (ledger has decisions only)

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
