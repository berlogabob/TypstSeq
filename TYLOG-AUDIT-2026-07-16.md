# TyLog Audit — 2026-07-16 (re-audit)

Follow-up to `TYLOG-AUDIT-2026-07-15.md`, same frameworks: device-verified evidence chain, Nielsen heuristics + Fitts/Hick/Jakob/Miller/Doherty/Tesler, perf ranking, PKMS product pass. **Lens for this pass: local-first — the app must be fully usable from local storage, and sync must never degrade local use.**

Device: Nothing Phone (3) "Metroid", Android 16, real hardware via adb. Build: local profile build of the current working tree (includes the sync-retry fix from this session). Vault: `/sdcard/TyLog`, 1390 notes local / 1603 files remote.

---

## 1. What the previous audit fixed — verified on device/code

| 2026-07-15 finding | Status now | Evidence |
|---|---|---|
| Vault open stalls forever, fake-empty UI | **Fixed** | Notes render instantly on launch; index/search rebuild in background (`workspace_controller.dart:159-186` fast path) |
| No error surface on open failure | **Fixed** | `MaterialBanner` "Open failed: …" + Retry wraps every main screen (`app_mobile.dart:3050-3066`) |
| Settings tile vs sync dashboard contradiction | **Fixed** | Shared `syncStatusKind` machine feeds AppBar icon, Settings, dashboard (`app_mobile.dart:81-105`) |
| Silent data loss typing with vault closed | **Mostly fixed** | `save()` now sets visible "Waiting for vault…" status (`workspace_controller.dart:211-218`); no auto-flush on open, but editor is unreachable without a vault |
| SAF picker creates vault in mis-picked folder | **Fixed (different shape)** | `inspectVaultStorage` rejects non-empty non-vault folders with a reasoned dialog + retry loop (`app_mobile.dart:494-565`) |
| "Delete vault and files" unguarded | **Fixed** | Red warning dialog + typed-name confirmation (`app_mobile.dart:614-650`) |
| Journal eager ListView | **Fixed** | `_JournalFeed` uses `ListView.builder` (`app_mobile.dart:4612`) |
| 250 ms sync poll always on | **Fixed** | Poll now scoped to a running dashboard action, cancelled in `finally` (`app_mobile.dart:3663-3670`) |
| Autosave flush-on-pause missing | **Fixed** | `didChangeAppLifecycleState` flushes dirty state on pause/hidden (`app_mobile.dart:1764-1770`) |
| "Typst help" flagged as typo | **Non-issue** | Typst is the engine's real name; string is correct. Closed. |

## 2. Sync on Android + local storage — root-caused and fixed this session

**Symptom** (user report + device trace): initial sync of the 1603-file vault never completed. Two runs died with `HttpException: Software caused connection abort` at file 161/1603 and 173/1603; each retry advanced ~12 files. At that rate, bootstrap needed ~120 manual app restarts.

**Root causes** (from `.tylog/sync_trace.jsonl` on device):
1. First sync has no cursors, so nearly every file takes a per-file HTTP GET to hash-compare ("same-content" decisions) — a multi-minute crawl.
2. `_open` retried only *connection setup*; a mid-request socket abort (classic Android power-save/network-switch behavior) propagated to the worker loop where `firstError` aborted the **entire run**.
3. The ZIP-archive bulk path was gated to initial/recovered syncs only, so a *resumed* interrupted bootstrap could never use it and fell back to the per-file crawl.

**Fixes applied** (`lib/nextcloud_sync.dart`):
- `_retryTransient` wraps each per-path sync: I/O and timeout errors retry on the existing `connectionRetryDelays` before failing the run.
- Archive eligibility now depends only on how many cursor-less remote files exist (≥32 and ≥half the bytes), so resumed bootstraps download one ZIP instead of crawling.
- A mid-download archive failure falls back to per-file transfers instead of failing the run.

Tests: 2 new (`test/nextcloud_sync_test.dart` — transient-abort retry; resume-uses-archive), full suite green, `flutter analyze` clean. **Device-verified: the previously-impossible bootstrap completed in ONE 62-minute run** (trace `runId 1784154990408303`: 204 downloaded, 1 uploaded, 1397 skipped of which 1224 content-verified, 1 conflict, 1602 remote files) — vs. dying at file ~170 twice before the fix. The remaining conflict is surfaced in the UI ("Needs attention" banner + warning icon) and awaits user resolution; note a pending conflict suspends auto-sync until resolved (§3-L4).

## 3. Local-first findings (new, this pass)

| # | Sev | Finding | Evidence | Fix direction |
|---|---|---|---|---|
| L1 | **4** | **The index pipeline could not finish on device — three compounding causes, all FIXED and device-verified.** Symptom: "Rebuilding index: 1300/1390" frozen for >68 min (also surviving an app restart); `search-index.json.gz` stale since the previous day; Android killed the app for "excessive CPU while cached" (exit-info). The identical scan over the identical files completes in **0.7 s on macOS without an inspector** (repro harness: `packages/tylog_core/tool/scan_repro.dart`) — everything wrong was in the device inspection path: **(a)** `_inspectionFiles` read the ENTIRE vault (~1600 serial SAF reads, whole vault in RAM ×2) before the first metadata query could run — now restricted to `_system/` + attachments (note sources excluded); **(b)** `inspector.inspect()` — a per-note Typst compile that is seconds-to-unbounded on device — had **no timeout**; now capped by `typstInspectTimeout` (30 s), and after the first timeout the inspector is treated as dead for the rest of the scan (a wedged native worker would idle out every later query too), with per-note `metadata-query-failed`/`metadata-fallback` problems; **(c)** validation issued a **per-attachment `exists()`** — thousands of serial binder calls on a web-clip vault — now answered from one recursive listing. After the fixes the device pipeline runs to completion: scan 1594/1594 → `index.json` 1.7 MB → validation + search build → `search-index.json.gz` **3.76 MB written 04:02** (first fresh search index in ~2 days). 3 new tests in `tylog_core`. | Mac repro 0.7 s; attached-console runs before/after; fresh index files on device | Done. Follow-up: native-side compile cancellation would reclaim a genuinely runaway Rust worker; consider surfacing "N notes pending metadata" instead of silent fallback |
| L2 | 3 | **No day rollover.** At 00:18 on Jul 16 the Today screen still shows "Wed, July 15". App open across midnight (or resumed next day) keeps serving yesterday as "today". | Screenshot 00:18 | Refresh today-date on resume + on a coarse timer |
| L3 | 3 | **25 s cloud poll keeps firing while app is backgrounded** — battery + data cost with zero user benefit; on Android background sockets get killed anyway (see §2). | `startCloudPolling` timer only cancelled on dispose (`workspace_controller.dart:337-344`, `:632-636`) | Pause timer on `AppLifecycleState.paused`, restart on resume |
| L4 | 2 | Background sync failure is visible only as a quiet AppBar icon change; a *pending conflict silently suspends all auto-sync* (poll skips when `hasSyncConflicts`), compounding into "sync is stuck" perception. | `workspace_controller.dart:341`; shared status machine | Snackbar once per new failure/conflict; dashboard already exists |
| L5 | 2 | Sync progress has no surface on main screens during bootstrap (only the sync icon spins); user can't tell 10 min of heavy I/O is progress, not a hang. | Device session | Reuse the rebuild-banner pattern for `syncStage` during `setup`/large runs |

**Local-first fundamentals that now hold** (keep them): notes usable instantly on open; search builds in background; sync runs off the open path; checkpoint-resume every 10 files; conflict copies never overwrite local edits (`canReplaceLocal` + conflict snapshots).

## 4. Perf (code-verified, unchanged from prior audit unless noted)

| Cause | Where | Fix |
|---|---|---|
| Eager `for`-loop ListViews on big lists — Library notes/articles (~1373!), entities, tasks, calendar; knowledge_screen search + problems | `app_mobile.dart:4754, 4780, 4809, 4838`; `knowledge_screen.dart:99, 134` | `ListView.builder` (mechanical) |
| Typst preview recompiles on every keystroke in preview/split modes | `app_mobile.dart:2949-3007` → `typst_document_viewer.dart:162` | 400 ms debounce (compile itself is already off-isolate via FRB) |
| Autosave debounce 700 ms (Doherty budget 400 ms) | `workspace_controller.dart:207` | 400 ms (flush-on-pause already exists) |
| Global `setState(() {})` rebuilds whole 5060-line shell on every workspace change | `app_mobile.dart:268`, `:2876` | Scoped `ListenableBuilder`s — larger refactor, do after the mechanical wins |
| `app_mobile.dart` at 5060 lines | — | Split by destination (maintainability) |

## 5. UX heuristics (device screenshots, this session)

| Sev | Screen | Violation | Finding → Fix |
|---|---|---|---|
| 3 | Library | Nielsen #10, Hick | Sixth tab shows as "En" at the screen edge. Correction to the 2026-07-15 finding: the TabBar is already `isScrollable: true`, so this is normal scrollable-tab overflow, not truncation — `tabAlignment: TabAlignment.start` added for clarity; the real issue remains 6 imposed taxonomy tabs (unified list + filter chips stays the product bet) |
| 3 | More sheet | Nielsen #6 | Settings still below the fold (9 items, must scroll, no scroll affordance). → Reorder: Settings into first screenful |
| 3 | Vault kebab | Fitts, error prevention | "Forget vault" still executes instantly, adjacent to Delete, same styling. → Confirmation + divider + destructive color |
| 3 | Split editor | — | Still unconditional 50/50 horizontal `Row` on phones (`app_mobile.dart:2985-3006`). → Stack vertically under 600 dp |
| 2 | Rich↔source switch | Nielsen #5 | Undo/redo history still cleared on every mode switch (`rich_editor.dart:648-660`). → Preserve stacks when content unchanged |
| 2 | Capture | Doherty, product | Still no quick capture: More → New page → title → template. → FAB/long-press (product bet, defer) |

## 6. Fixes applied this pass (subagent-executed, reviewed, all gates green)

Executed via one implementer subagent per task + per-task diff review + a final whole-branch review (verdict: ready). `flutter analyze` clean, `flutter test` 216 pass / 1 skip after all changes.

1. **Sync resilience** (§2) — retry + archive-resume + archive fallback in `nextcloud_sync.dart`; device-verified full bootstrap.
2. **ListView.builder ×6** — Library notes/articles, entities, tasks, calendar day list; knowledge search + problems (`app_mobile.dart`, `knowledge_screen.dart`). Search field given a persistent controller so scroll-eviction keeps its text.
3. **Preview debounce 400 ms** in preview/split (immediate first render) + **autosave 700→400 ms**.
4. **Cloud poll paused on background, restarted on resume**; **day rollover on resume** (pure `shouldRolloverToday` helper + tests; skips when edits are dirty — edits win).
5. **UX**: Forget-vault → "Disconnect (keep files)" with confirmation dialog; "Delete permanently…" in error color behind a divider; Settings moved to slot 2 in the More sheet; split mode stacks vertically under 600 px.

## 7. Open follow-ups, in order

1. ~~§3 L1~~ — **resolved during this pass** (see the L1 row: inspection preload, inspect timeout + dead-marking, validation listing). Remaining nicety: native compile cancellation.
2. §3 L4/L5: proactive snackbar on new sync failure/conflict; sync progress surface during large runs (only the AppBar icon spins today).
3. Resolve-then-verify the one bootstrap conflict on device (user action; auto-sync is suspended until then).
4. Global `setState` → scoped rebuilds; split `app_mobile.dart` (5060 lines).
5. Product bets unchanged from 2026-07-15 §4 (quick-capture FAB, `[[wikilink]]` sugar, Context panel promotion, unified Library, read-later view for articles).
