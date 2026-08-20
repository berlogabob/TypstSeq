# "Tine" and the Logseq file-format fork question (as of 2026-08-20)

## Identity verdict — read this first

A real, actively-developed project named **Tine** exists and is genuinely
positioned as a Logseq-compatible, file-based alternative:
[github.com/martinkoutecky/tine](https://github.com/martinkoutecky/tine)
(website [tine.page](https://tine.page/)). **But it is explicitly, repeatedly
NOT a fork** in the git-lineage sense — the maintainer states in the README
and on the site that it is "an independent reimplementation, not a fork" with
"original Rust and SolidJS containing no Logseq source." It targets Logseq's
on-disk Markdown format and adapts parts of Logseq's outliner CSS, which the
maintainer says makes it "a derivative work for licensing purposes" (hence
inheriting Logseq's AGPL-3.0 license), but there is no shared codebase, no
forked git history, and no PR relationship to `logseq/logseq`.

If the premise behind the ask was "a community fork that continues
file-based Logseq after the DB-version pivot," Tine is the closest known
real match — but the correct one-line correction is: **it's a from-scratch,
Logseq-format-compatible outliner, not a fork.** No evidence was found of a
project literally forked from the `logseq/logseq` repository and renamed
"Tine." I searched GitHub, Logseq's own forum (discuss.logseq.com), and
Hacker News (via Algolia) for any announcement of a fork named Tine — none
exists. Two unrelated repos surfaced in general "logseq fork" searches
(`Team-R3SET/logseq-fork`, `stevelab1/logseq-fork-2026`) — both are
low-signal/unclear-purpose repos with no connection to "Tine" and are not
discussed further here. No unrelated "Tine 2.0"/Tine Groupware (PHP
CRM/groupware suite) or npm/design-tool namesake collision was found in the
Logseq context — the name doesn't appear contested.

Primary sources fetched 2026-08-20 (today): GitHub repo page + API, raw
README, `docs/FEATURES.md`, `CONTRIBUTING.md`, releases page, tine.page
homepage, tine.page/compare.html.

## 1. Provenance

- **Repo created**: 2026-06-24 ([GitHub API](https://api.github.com/repos/martinkoutecky/tine), `created_at: 2026-06-24T21:59:31Z`) — under two months old as of this research.
- **Not forked from any Logseq commit/version.** GitHub's own fork flag confirms this: `"fork": false` in the repo API response. It is a ground-up rewrite that targets Logseq's *file format* (journals/, pages/, assets/, logseq/config.edn), not its codebase.
- **Maintainer**: Martin Koutecký (GitHub handle `martinkoutecky`), a single named human maintainer. Contributors per GitHub API: 3 total (`martinkoutecky`, `da5nsy`, `EllisMorrow`), overwhelmingly maintainer-driven.
- **Notable authorship claim**: tine.page states "Tine is built by Claude Code (AI) under human direction and review by Martin Koutecký," with the creator "emphasizing transparency about AI-assisted development while maintaining human oversight" ([tine.page](https://tine.page/), fetched 2026-08-20). `CONTRIBUTING.md` corroborates: implementations are "often AI-assisted" during review, after a human-approved design proposal.
- **Stated motivation** (maintainer's own words, README/tine.page): "Logseq's UI is Electron + DataScript with heavy re-rendering, and it gets sluggish on large graphs." The fix chosen was not forking Logseq's code but "a ground-up rewrite: a small native shell (Tauri/WebKitGTK), a pure-Rust core for parsing and indexing, and a fine-grained reactive frontend (SolidJS)." This is a **performance/architecture complaint, not a DB-version-migration protest** — the DB-version pivot is not cited anywhere in the primary sources as the motivating grievance. The site does note Tine intentionally excludes "database-version Logseq support," i.e., it targets file/Markdown Logseq by design, but frames this as staying focused rather than reacting to the DB pivot.
- **License**: GNU AGPL-3.0-only ([repo license file](https://github.com/martinkoutecky/tine), confirmed via GitHub API `license.spdx_id: AGPL-3.0`), inherited because the project is "a derivative work for licensing purposes" of Logseq's format/CSS.
- **Governance**: single-maintainer, closed-PR model for code (see §4).

## 2. Divergence from Logseq OG — and the core premise check

**Core premise confirmed**: Tine is genuinely file/Markdown-based and
interoperable with Logseq's on-disk graph. Per
[tine.page/compare.html](https://tine.page/compare.html) and the README, it
"Reads and writes the *same* markdown graph as Logseq — swap between the two
on the same files," reading `.md`/`.org` files under `journals/`, `pages/`,
`assets/`, and `logseq/config.edn`, with no import/export step required.
Files stay plain Markdown that the user fully owns.

Features added beyond Logseq OG (per
[FEATURES.md](https://github.com/martinkoutecky/tine/blob/master/docs/FEATURES.md)
and [compare.html](https://tine.page/compare.html)):
- **Sheets**: 2-D grids, typed field tables, Kanban/tag boards, formula columns, built on plain Markdown blocks.
- **Split view**: independent panes, tabs, per-pane history.
- **Built-in browser-style tabs**, persistent search-as-workspace tabs.
- **Global quick-capture** via desktop hotkey from any application.
- **Task carry-forward**: rolls unfinished tasks forward by configurable timeframe.
- **Native PDF annotation** with highlights, area highlights, reader themes — "Logseq has no native PDF export — only a community plugin" (compare.html).
- **Native PDF export** per page.
- Performance: native Rust/Tauri/SolidJS core instead of Electron/DataScript, explicitly targeting large-graph sluggishness.
- Android: native arm64 app (Tauri v2) as of v0.4.0, editing the same Markdown files, sideloaded APK.

Deliberately removed/out of scope (compare.html, "Deliberately Out of
Scope"): whiteboards/canvas as a native tool (external drawio/Excalidraw SVG
round-trip supported instead), flashcards/spaced repetition, Logseq or
Obsidian plugin-API compatibility, real-time multi-user collaboration, and
DB-version Logseq support.

Query engine is intentionally scoped down: "supports everyday queries but
not raw Datalog with arbitrary entity joins or custom rules" — unsupported
Datalog clauses are flagged rather than silently ignored (compare.html).

Graph view (node-link visualization) is **not yet implemented**; only
"local-neighborhood visualization is planned" (compare.html).

## 3. Sixteen-row taxonomy

| Row | Tine status | Source |
|---|---|---|
| **Note model** | Inherited concept (blocks, outline, `key:: value` properties, `id::`), full Markdown/Org round-trip. Unchanged in spirit from Logseq OG. | [FEATURES.md](https://github.com/martinkoutecky/tine/blob/master/docs/FEATURES.md) |
| **Editor** | Full Logseq-style keyboard semantics (Enter/Tab/Shift-Tab/Backspace), block zoom/collapse, wrap-then-type, callouts, sanitized inline/block HTML — plus additions (typographic replacement, calculator slash command). Not a plain "inherited, unchanged" row — meaningfully re-implemented and extended. | FEATURES.md |
| **References** | Page refs, hashtags, block refs `((id))`, embeds `{{embed}}`, autocomplete, linked/unlinked-reference panels, hover previews — parity claimed with Logseq. | FEATURES.md, [compare.html](https://tine.page/compare.html) ("Full Parity ✓" list) |
| **Tasks** | TODO/DOING/DONE/NOW/LATER/WAITING/CANCELED states, two workflows, priorities, LOGBOOK time-tracking (OG-compatible), SCHEDULED/DEADLINE, recurring tasks — plus Tine-only task carry-forward. | FEATURES.md |
| **Queries** | Query DSL parity for common cases (`task`, `priority`, `property`, `between`, etc.) plus visual/no-code query builder; explicitly **not** full raw Datalog with joins/custom rules. | compare.html ("Partial/Scoped ◑: Queries") |
| **Graph (visualization)** | **Not implemented.** "Not yet implemented; local-neighborhood visualization is planned." | compare.html |
| **Search** | Ctrl+K quick switcher, full-text, search syntax (phrases/regex/exclusions), ranking, in-page find, persistent search-as-workspace. Extended beyond OG. | FEATURES.md |
| **Sync** | No cloud sync backend of its own; filesystem watcher (inotify/poll), never silently overwrites externally-changed files, and dedicated conflict-merge UI for Syncthing/Dropbox `*.sync-conflict-*` files (block-by-block diff by `id::`). | FEATURES.md ("Sync & Conflict Resolution": "Absent: Cloud sync backend; native Syncthing integration.") |
| **Import/export** | Static HTML publish (own `public::`-page exporter, offline full-text search), PDF export per page, Markdown/Org copy-export. No direct integration with Obsidian Publish/Notion-style platforms. | FEATURES.md |
| **Storage** | Same flat-file Markdown/Org graph as Logseq OG (journals/, pages/, assets/, logseq/config.edn); namespaces stored as flat `parent___child.md` files, not real folders — this matches Logseq OG's own convention. | FEATURES.md, tine.page |
| **Plugins** | **Original Logseq plugins do NOT work.** Tine ships its own experimental WASM-based plugin API (v0.2) with no DOM/file/network access, and a separate token-based theme API — explicitly stated as no JS-plugin compatibility: "Absent: JavaScript plugin API; Logseq `@logseq/libs` or Obsidian API compatibility." | FEATURES.md ("Plugins & Extensions") |
| **Whiteboards** | No native canvas tool. Supports external drawio/Excalidraw round-trip (`/drawio` creates an editable SVG asset, opens in the external editor). | FEATURES.md ("Whiteboards & Diagrams") |
| **SRS (spaced repetition)** | **Absent.** `{{cloze}}` renders only in a "degraded" click-to-reveal form with no scheduling/SRS engine behind it. | FEATURES.md |
| **PDF annotation** | Present and a stated differentiator: zoomable/virtualized PDF pane, text/area highlights, reader themes, outline nav — richer than Logseq OG's plugin-only PDF support. | FEATURES.md, compare.html |
| **Journals** | Multi-day continuous feed, journal templates, agenda view, calendar with markers, configurable date formats — parity plus extensions (carry-forward, agenda). | FEATURES.md |
| **Platforms/mobile** | Desktop: Linux (primary/best-tested), macOS and Windows ("newer builds"). Mobile: **Android only** (native Tauri v2 arm64, sideloaded APK, Play Store/F-Droid "planned"). **No iOS** — site directs iOS users to "Logseq mobile or fastlog" instead. | tine.page, FEATURES.md ("Mobile (Android)": "Absent: iOS app (being scoped)") |
| **Publishing** | Static HTML export with offline search (Fuse.js) and PDF export; no scheduled or multi-platform publishing. | FEATURES.md |
| **Licensing/governance** | AGPL-3.0-only, single primary maintainer, code contributions **explicitly not accepted as PRs** ("Tine does not merge externally-written code into the app" — contributors submit design proposals/specs instead; docs/typo PRs are the exception). | [CONTRIBUTING.md](https://github.com/martinkoutecky/tine/blob/master/CONTRIBUTING.md) |

## 4. Viability signals

- **Stars**: 311. **Forks**: 22. **Open issues**: 112. (GitHub API, fetched 2026-08-20.)
- **Contributors**: 3 total per GitHub API (`martinkoutecky`, `da5nsy`, `EllisMorrow`) — effectively a solo/AI-assisted project with light outside involvement, consistent with the "no code PRs" contribution model in CONTRIBUTING.md.
- **Commits**: ~2,797 on `master` (per repo page), against a repo only created 2026-06-24 — very high commit velocity for under two months, plausibly reflecting the stated AI-assisted implementation workflow.
- **Release cadence**: near-daily in the most recent stretch — v0.6.90 (Aug 5), v0.6.91 (Aug 7), v0.6.92 (Aug 11), v0.6.93 (Aug 12, 2026, latest at fetch time) — after a slightly slower mid-July run (v0.6.0–v0.6.5, Jul 18–22). [Releases page](https://github.com/martinkoutecky/tine/releases).
- **Status self-description**: "Usable daily-driver; not yet version 1.0" (repo page).
- **Prebuilt binaries**: Linux (AppImage, .deb, .rpm), macOS (.dmg), Windows (.exe + portable .zip), Android (sideloaded arm64 APK). No iOS build. All via GitHub Releases — no app-store distribution yet.
- **No forum/HN footprint found**: an Algolia HN search for "Tine Logseq" and "tine.page" returned no matching Show HN/story threads, and a discuss.logseq.com search for "tine" returned nothing. This suggests the project has not yet had a wide public launch moment (no HN front-page post, no Logseq-forum announcement thread) — it may be growing through direct GitHub/word-of-mouth discovery only. Community awareness signals (stars/forks) are still small.

## 5. Honest pros/cons

**Tine vs staying on Logseq OG (file-based):**
- *Pro*: faster on large graphs (native Rust/Tauri core vs Electron+DataScript); adds PDF annotation, sheets/kanban, split-view, and task carry-forward that Logseq OG lacks natively; files stay byte-compatible so switching is reversible any time.
- *Con*: no original Logseq plugin ecosystem (JS plugin API not supported — a real loss if you depend on community plugins); no native whiteboard; no SRS/flashcards; no graph visualization yet; single-maintainer/AI-assisted project barely two months old with only 311 stars — much higher abandonment/instability risk than an established Logseq OG install; no iOS.

**Tine vs moving to Logseq's new DB version:**
- *Pro*: keeps notes as plain Markdown files under full user control (no SQLite/datascript lock-in — see this repo's own [research-logseq-db-format.md](./research-logseq-db-format.md) for how opaque the DB-version storage is); avoids the DB version's migration risk and format churn entirely; arguably faster than either Logseq variant given the from-scratch native core.
- *Con*: the DB version gets Logseq's own ongoing investment (official product, presumably eventual mobile/sync maturity, official plugin ecosystem evolution); Tine explicitly does not support the DB format at all, so it's not a bridge to that world — picking Tine is a bet on staying file-based indefinitely, maintained by one person, not a hedge against Logseq's own direction.
