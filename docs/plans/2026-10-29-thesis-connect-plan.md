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
- [ ] Keyboard up: hide Agenda row too; Screenshots and Linked references collapsed under More
- [ ] Add `docs/audio-transcription.md` to bundled RAG doc lists
- [ ] `graphify update .`

### P1 Conceptual data model (supervisor's ask) -> `docs/thesis/conceptual-model.md`
- [ ] Entities: Item, Mention, Entity, Link, Source; attributes `source` (typed, OCR, ASR, OLT, ICS, contacts) and `derivation` (typed, extracted, confirmed)
- [ ] ER diagram (Mermaid) with real vault field names; OLT table mapping
- [ ] One-page "novelty" statement + what is measured (accept rate, gold set)

### P2 Graph source filter
- [ ] Source on every node (daily, note, screenshot, audio, article, event, external)
- [ ] Filter chips beside the edge-kind legend; cluster by source option
- [ ] Tests + device check

### P3 Extraction coverage
- [ ] Decide: enrich audio transcripts (yes) and screenshots (user decision)
- [ ] Audio notes get tags/aliases from transcript; enrichment runs on `kind: audio`
- [ ] Re-queue backlog without a PROMPT_VERSION bump (2 h of Studio compute)

### P4 Settings sharing
- [ ] `*.local.json` never syncs (`isSyncableVaultPath`), reads merge `x.json` + `x.local.json`
- [ ] Per-section switch "Sync across devices / This device only"; calendars first (feed URLs hold tokens)
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
- [ ] Outlook calendar via ICS feed (existing `calendar_feeds.dart`); contacts via vCard/CSV import for autocomplete

### P9 Evidence for the thesis
- [ ] Gold-set evaluation: Dart resolver CLI, 100-200 labelled mentions, resolver with vs without ledger
- [ ] Log ignored suggestions too (ledger has decisions only)

## Issue log
- 2026-10-29: P30 not on adb; Nothing Phone 3 (A024, serial 000251565001005) is the test device now.
- 2026-10-29: Windows updater hang cause unconfirmed; ask for `%TEMP%\tylog-update.log` after the next update.
- 2026-10-29: Portuguese pack repo has uncommitted lesson edits; built pack may be stale.

## Tick log
