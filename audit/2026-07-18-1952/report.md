# UX/UI Audit — TyLog (macOS desktop + Android, v0.1.0+65 / ec99ac2) — 2026-07-18

## Executive Summary

**Release verdict: READY WITH FIXES.** No severity-4 (release-blocking) issues; the app is
stable, navigable, and every defined user flow completed. **25 findings** after dedup —
**0 sev-4, 7 sev-3, 13 sev-2, 5 sev-1** — across 30 screens (21 macOS + 9 Android). Task
success rate was **100% (6/6 flows)** at ~4.7 steps/flow, though two flows exposed defects.

> **Follow-up (Android real-vault re-run + "stuck sync" diagnosis) appended below.** The
> vault was re-synced to real content (full parity with macOS); the "stuck sync" was root-caused
> to a long silent first-sync/index with no progress UI — elevating **F-020 to sev-3** and adding
> **F-025** (re-index-on-navigation churn).

> **UPDATE — all 25 findings implemented** on branch `ux-audit-fixes` (6 commits off ec99ac2),
> `flutter analyze` clean, 281 tests passing, `flutter build macos --release` succeeded, and 13
> findings visually confirmed on the built app (dark mode, overdue flag, clean search subtitles,
> plain-language + colour-coded Problems, non-contradictory Settings status, focused Graph, etc.).
> Branch left unmerged for review. See "Fixes implemented" at the end of this report.

The three issues to fix first:
1. **Internal data leaks into the UI** — every Search result shows the on-disk `.typ` path plus a raw record id with a trailing JSON comma (`id: "md-…",`); Settings has a `Fold legacy properties["type"] entities into kind` action; the Android vault path is shown as a raw `content://…` SAF URI. Users see developer internals throughout.
2. **The Problems screen dumps raw Typst compiler errors** (`[ERROR] 149:94 — emph does not have field "Instead"` · 17 notes) with no note names, no jump-to-source, and no fix action — an error surface a user can't act on.
3. **Contradictory & derailing states** — Settings says "Folder access unavailable" while the Sync detail says "Permission and safe writes verified" for the same vault; and Android first-run onboarding let the vault grant land on an empty Downloads folder with no recovery, silently starting a blank vault.

## Background & Objectives

TyLog is a Flutter journal / PKMS app (single-shell architecture, `lib/app_mobile.dart`).
Audited on the user's request for a full crawl of both shipping targets. App v0.1.0+65,
commit ec99ac2. Targets: macOS 15.7.4 (real vault `~/Nextcloud/TyLogVault`, ~1698 notes /
1676 articles) and a connected Android 10 device (ELE L29, `XPH0219904001750`). This is the
baseline run — no prior audit to trend against.

## Methodology

- **Crawl:** 30 distinct screens saved as screenshots (see `screens.md`). macOS covered every
  major surface with real content; Android covered the nav structure + empty/onboarding states.
- **Flow suite (6):** cold-start→Today, Android onboarding/vault-grant, full-destination
  navigation, editor view-modes, settings→sync, and the destructive delete-vault confirmation
  (captured then **cancelled** — no data touched). Results in `flows-results.json`.
- **Frameworks:** Nielsen's 10 heuristics, UX laws (Fitts/Hick/Miller/Jakob), visual design
  (typography/color/Gestalt/WCAG — judged visually), design-system consistency (incl. macOS↔Android
  parity), the 5 system states, and ISO 9241-11 / HEART. Five parallel subagents, one per dimension.
- **Tooling / constraints:** Maestro CLI installed; adb + macOS Swift-clicker driving. **The
  Flutter release build exposes no accessibility/semantics tree** — Maestro and macOS AX both
  returned SystemUI-only hierarchies, so the crawl was coordinate/screenshot-driven and
  **`measure.py` produced no deterministic numbers** (tap-target/Miller/alignment/contrast are
  hierarchy-keyed). Size/contrast findings are therefore visual judgements, not measurements.
- **NOT covered:** Reading mode, Split editor, Context/backlinks, Typst-help; real note
  create/edit/delete (no discoverable note-delete affordance → a scratch note would leak a file);
  Android populated content (granted folder was an empty Downloads dir, Nextcloud not reconnected
  post-reinstall); an isolated loading-state capture.

## Metrics

| Metric | Value | Source |
|---|---|---|
| Task success rate | 100% (6/6 flows completed) | flows-results.json |
| Avg steps / flow | 4.7 | flows-results.json |
| Flows exposing defects | 2/6 (onboarding→wrong folder; settings→sync contradiction) | flows-results.json |
| Screens audited | 30 (21 macOS + 9 Android) | screens.md |
| Findings by severity | sev-4: 0 · sev-3: 7 · sev-2: 13 · sev-1: 5 | findings.json |
| Defect density | 0.8 findings / screen | derived |
| Deterministic measurements | unavailable (no a11y tree) | measurements.json |

### HEART (framework mapping)
| Dimension | This audit's proxy | Read |
|---|---|---|
| Happiness | 6 sev-3, 0 sev-4 | Moderate friction; no blockers |
| Engagement | Core nav loops fast (≤8 steps) | Good |
| Adoption | First-launch flow **derails** on Android (F-005) | At risk |
| Retention | Error recovery weak (F-002 unactionable errors; F-020 no loading states) | At risk |
| Task success | 100% completion, 4.7 steps | Measured, good |

No in-app analytics events were observed. **Instrumentation recommendation:** add events for
onboarding completion + vault-folder outcome (Adoption), core-loop step counts (Engagement),
and error-surface encounters (Retention) so these proxies become measured signals.

## Key Findings

### Severity 3
- **F-001 · H2 · macos:09-search** — Search results leak the raw `.typ` path + internal `id: "md-…",` (trailing comma included) in every subtitle; same on android:06. → Show title + short source only. `screens/macos/09-search.png`
- **F-002 · H9 · macos:21-problems** — Raw Typst compiler error shown verbatim (`[ERROR] 149:94 — emph does not have field "Instead"` · 17 notes) with no note names / jump / fix. → Plain-language problems, link the offending notes, tap-to-open. `screens/macos/21-problems.png`
- **F-003 · H1 · macos:11-settings** — Settings "Folder access unavailable" contradicts Sync detail "Permission and safe writes verified" (both platforms). → One status source of truth. `screens/macos/11-settings.png`
- **F-004 · H2 · macos:11-settings** — `Migrate entity types — Fold legacy properties["type"] entities into kind`: raw schema jargon as a user action. → Auto-run in background or reword plainly. `screens/macos/11-settings.png`
- **F-005 · FLOW-1 · android:01-today-launch** — Vault grant landed on an empty Downloads folder, no guidance to the real vault, no recovery → silent blank vault. → Post-grant "folder is empty — re-pick?" recovery card. `screens/android/01-today-launch.png`
- **F-006 · ST-EMPTY · android:04-library** — Empty Notes tab is a blank white void (no message, no create action) — reads as broken, and is a dead end; inconsistent with Articles/Entities empties. → Add a designed empty state + inline create. `screens/android/04-library.png`

### Severity 2
- **F-007 · H2 · android:08-settings** — Vault shown as raw `content://…downloads.documents/tree/raw%3A…Download%2FTyLog`; macOS shows a clean path. → Decode to a readable path.
- **F-008 · H8/LAW-HICK · macos:17-graph** — Graph defaults to an unreadable 1698-node hairball (app admits "this can get hard to read"); low stroke contrast. → Default to Focused view + higher contrast.
- **F-009 · H4 · macos:05-library-articles** — Article status vocabulary inconsistent (chips All/Inbox/Reading/Read vs badges Read/Unread/processed) and monochrome pills. → Unify terms + semantic color.
- **F-010 · H8 · macos:03-library-notes** — Redundant `.typ` file-path subtitles echo the title across Notes/Today/Calendar/Graph. → Replace with useful metadata.
- **F-011 · VD-HIER/DS-NAV · macos:03** — App-bar title alignment inconsistent (Library/Search centered vs Today/Journal/Graph left) across the same shell + on Android. → One title convention.
- **F-012 · VD-LAY/DS-SPACE · android:04** — Android app-bar titles flush at x=0 and clipped (no leading inset). → Apply ~16dp leading padding.
- **F-013 · VD-RESP · android:08-settings** — Narrow Android sheet breaks text mid-word and clips ("Androi/d.providers", "Migrate entity/types"). → Adapt padding, middle-ellipsis URIs, wrap on word boundaries.
- **F-014 · DS-FDBK · macos:11** — Three modal patterns for peer More-menu targets (dialog vs bottom-sheet vs full-screen) + divergent sheet internals. → One sheet template + one presentation rule.
- **F-015 · DS-FORM · macos:06-library-tasks** — Task checkbox drawn three ways (filled Material / outlined square / inline strikethrough glyph). → One shared checkbox component.
- **F-016 · DS-COL · macos:01** — Light ColorScheme only; no `darkTheme`/`themeMode` wired (verified in `lib/app_mobile.dart:93`) → app stays light under OS dark mode; scattered `Color(0x…)` literals won't adapt. → Add a dark scheme + tokenize colors.
- **F-017 · LAW-MILLER · macos:16-magic-menu** — Flat 18-tile Magic palette, no grouping, mixes insert + text-format intents. → Chunk into labeled groups.
- **F-018 · VD-COL · macos:21-problems** — Severity icons (error/warning/info) all monochrome black — no semantic color. → Tint red/amber/neutral.
- **F-019 · ST-EMPTY · android:03-journal** — Empty day card is bare, no "Start writing…" affordance (which Today has). → Add placeholder + journal CTA.
- **F-020 · ST-LOAD · macos:17** — No loading/progress state observed for heavy ops (index rebuild, graph, metadata). → Verify/add skeleton/progress.

### Severity 1
- **F-021 · LAW-FITTS/VD-HIER · macos:20** — Destructive "Continue" is the loudest button on the no-recovery delete-vault dialog; vague label. (Mitigated by a 2nd type-name gate.) → De-emphasize + rename "Delete permanently".
- **F-022 · H1 · macos:06** — Overdue task (due 2026-07-06, 12 days past) styled like on-time tasks. → Flag overdue.
- **F-023 · LAW-FITTS · android:02** — Small AppBar/date-chevron touch targets (~≤40dp) in top corners. → ≥48dp touch areas.
- **F-024 · VD-TYPE · macos:01** — Lightest placeholder/secondary grays look borderline on near-white (unmeasured). → Verify WCAG 4.5:1.

## Recommendations (prioritized)

1. **Stop leaking internals to users** (F-001, F-004, F-007, F-002, F-010): strip ids/paths/URIs
   and dev jargon from Search, Settings, list subtitles, and Problems. This single theme accounts
   for four of six sev-3s and is mostly copy/formatting work — highest value per effort.
2. **Fix status truthfulness & onboarding recovery** (F-003, F-005): one sync-status source;
   post-grant empty-folder recovery. These undermine trust and adoption.
3. **Empty & error states** (F-006, F-019, F-002, F-018, F-020): give Notes/journal real empty
   states with a next action; make the error surface actionable and color-coded.
4. **Design-system debt worth batching** (F-011–F-016): one app-bar title/inset convention, one
   sheet/modal template, one task-checkbox component, a dark ColorScheme + color tokenization,
   and macOS↔Android header parity. These are cross-cutting and cheaper fixed together.
5. **Instrumentation** (HEART): add onboarding-outcome, core-loop-step, and error-encounter events.
6. **Polish** (F-021–F-024): destructive-button emphasis, overdue flag, touch-target sizing, contrast check.

## Follow-up — Android real-vault re-run & "stuck sync" diagnosis (2026-07-18, same run)

After the baseline audit, the Android vault was pointed at the real Nextcloud vault
(`https://nextcloud.soundingdoubts.pt`, admin · TyLogVault) and the user reported sync looked
stuck. Investigated systematically (evidence before fixes), using the fact that the vault lives
in shared storage (`/storage/emulated/0/Download/TyLog`) and is directly readable via adb:

- **Boundary 1 — Nextcloud → disk: OK.** 1703 `.typ` files present (5 notes / 1676 articles /
  15 daily / 2 projects) = full parity with macOS; newest files timestamped 21:37 (download done).
- **Boundary 2 — disk → index: OK but slow.** `_index/index.json` reached 1.9 MB / **1701 entries**;
  the app burned **17+ min of CPU**; polling showed the index stable and all 67 threads sleeping
  (idle) once complete — i.e. **not a deadlock**, a long grind.
- **Boundary 3 — index → UI:** once the index finished, the Library populated correctly (Notes,
  Today, Search, Articles all show real content; cloud icon flipped to synced).

**Root cause of "stuck sync":** not a wedge — a genuine first-time full sync + whole-vault index
of a large vault (~1700 files) over a slow **roaming** link (rsrp −70, sub-1 KB/s), during which
the UI showed an empty list with only a fading toast. This is **F-020** biting for real (now
**sev-3**). A secondary behavior surfaced: re-probe/re-index fires on every Library navigation even
after indexing completes, janking tab switches (**F-025**, sev-2).

**Outcome:** Android is now at full content parity with macOS; the cross-platform findings
(Search `id:` leak F-001, redundant `.typ` subtitles F-010, article-status vocabulary F-009) are
confirmed on Android real content. The empty-state findings F-006/F-019 were the first-run/empty-
vault state and now populate correctly — but the *first-run large-sync* empty appearance they
share with F-020 remains the real concern. Real-content Android captures saved as
`screens/android/r02-today.png`, `r03-journal.png`, `r05-library-articles.png`, `r06-search.png`.

## Fixes implemented (2026-07-18)

All 25 findings were implemented on branch `ux-audit-fixes` (6 commits off ec99ac2), delegated to
codex in-repo and reviewed + verified per batch. **Not merged** — left for review.

| Batch | Findings | Notes |
|---|---|---|
| 1 | F-016, F-024 | Dark ColorScheme + `themeMode.system`; graph/editor colors brightness-aware; muted/hint tokens darkened |
| 2 | F-011, F-012, F-014, F-021, F-023 | Left-aligned titles; restored AppBar inset; Settings→bottom sheet; delete-vault de-emphasized + "Delete permanently"; ≥48dp touch target |
| 3 | F-003, F-004, F-007, F-013 | One sync-status source; plain-language migrate copy; SAF-URI→readable-path decoder (+test); no mid-word wrapping |
| 4 | F-006, F-009, F-010, F-015, F-019, F-022 | Empty Notes/Projects states; article status vocab+color; dropped `.typ` subtitles; shared TaskCheckbox; overdue flag; journal "Start writing…" |
| 5 | F-001, F-002, F-008, F-017, F-018 | Clean search subtitles; Problems plain-language + `detail` + note names + tap-to-open; colored severity icons; graph opens focused; grouped Magic palette |
| 6 | F-005, F-020, F-025 | Empty-folder re-pick recovery; first-sync/index progress + "Indexing…" states; conservative poll change-detection gate (`canSkipPoll`, +tests) |

**Verification:** `flutter analyze` clean; **281 tests passing** (main) + `tylog_core` core_test; new
tests for the URI decoder, overdue detection, and the poll gate; `flutter build macos --release`
succeeded. The `tylog_core` `cli_test` PDF-export case times out in this environment — confirmed
**pre-existing** (fails identically on the pre-change tree), unrelated to these changes. 13 findings
were visually confirmed on the built macOS app (screenshots in the run's scratchpad): dark mode
(F-016), overdue (F-022), no `.typ` subtitles (F-010), shared checkbox (F-015), clean search
(F-001), Problems plain-language + colored icons (F-002/F-018), Settings status/copy/path + sheet
(F-003/F-004/F-007/F-014), focused Graph (F-008), left-aligned titles (F-011).

## Appendix

- **Screen inventory:** `screens.md` (30 screens; hierarchy dumps unavailable — no a11y tree).
- **Flow results:** `flows-results.json` (6 flows, 100% completion).
- **Measurements:** `measurements.json` — `available:false`; Flutter release build exposes no
  semantics tree, so deterministic tap-target/Miller/alignment/contrast numbers could not be
  computed. Re-run against a profile/debug build (or with the semantics tree enabled) to unlock them.
- **Note on cross-cutting duplicates:** the Sync-status contradiction, Search leak, Graph
  hairball, article-status vocabulary, title alignment, and Android raw-URI were each flagged by
  multiple subagents; merged here under a primary criterion with the others recorded in each
  finding's `also` field in `findings.json`.
