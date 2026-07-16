# TyLog Audit — 2026-07-15

Device: Nothing Phone (3) "Metroid", Android 16, 1260×2800 @480dpi, real hardware via adb.
Build audited: installed release **1.0.0+57** (installed today 07:44). Vault: `/sdcard/TyLog` (SAF tree `primary:TyLog`), **1390 notes** on disk (1373 articles, 11 daily, 4 notes, 2 projects).

---

## 1. Why it "works strange" — root cause found

**The vault never opens. Every screen shows a fake-empty state instead of an error.**

Evidence chain (all verified on device):

1. The vault on disk is healthy: `_index/index.json` (1.4 MB) parses cleanly and lists all 1390 notes with correct kinds; sync trace shows `"conflicts":0` throughout.
2. On every app launch, `openVault` gets as far as `rebuildIndex` — it rewrote `_index/index.json` at 14:02 and again at 14:08 (launch times).
3. It never reaches the end of the pipeline: `_index/search-index.json.gz` was last written at **09:22** and is never updated; the app process sits at ~0% CPU (7s total) — not working, not crashed, just **suspended on an await**.
4. The stall is inside `_readPkms` (`lib/workspace_controller.dart:506-522`): search-index load/build issues **sequential per-file SAF reads** (`packages/tylog_core/lib/src/search_index.dart:147-173` — `await storage.readText(note.path)` in a loop over up to 1373 articles), with **no timeout, no progress callback, no error surfacing**. One unresolved platform-channel read = vault open hangs forever.
5. Because `openVault` only assigns `vault`/`index` **after** the whole pipeline finishes (`workspace_controller.dart:105-161`), the UI keeps `index == null` and renders "Start writing…", "No journal pages yet", empty Library — indistinguishable from a brand-new vault.
6. The only place the truth appears is the sync dashboard semantics: *"Vault not open"*, *"Folder access or safe writes unavailable"* — 3 levels deep (More → scroll → Settings → Sync).

Contributing events found on the device:

- The app was **uninstalled/reinstalled today** (firstInstallTime 07:44; vault files still owned by the previous install's uid `u0_a265`, app now runs as `u0_a486`). Reinstall silently wiped the persisted SAF grant and app-local state — the re-auth flow then has to run, and the pipeline above never completes.
- Settings tile says **"Sync: Not configured"** while the sync dashboard on the same install shows the configured server (`nextcloud.soundingdoubts.pt · admin · TyLogVault`) — two widgets compute status from different sources.
- A stray `.tylog` vault marker exists in **`/sdcard/Audiobooks/`** (created 01:33 today): the picker flow once initialized a vault inside a mis-picked folder with no confirmation step.
- `daily/2026/07/2026-07-16.typ` (tomorrow) was created today at 12:58 — day-rollover/timezone logic worth a look.
- Typing into the Today editor while the vault is closed is accepted but **silently discarded** — `save()` returns early with no warning (`workspace_controller.dart:177-179`). Data-loss risk.

### Fixes, in order of leverage

1. **Never gate the UI on the full open pipeline.** Load the persisted `_index/index.json` first (it's already there and correct) and show content immediately; rebuild index + search index in the background and swap in when done.
2. **Timeout + error surface on every SAF platform-channel call** (single wrapper in `vault_storage.dart`); a failed open must show a banner with the actual error and a Retry, not empty states.
3. **Make `status` visible on mobile.** It carries 'Opening vault…' / 'Open failed: …' but is rendered nowhere on the 5 main screens.
4. **Block typing (or buffer + warn) when `vault == null`.**
5. Reconcile the two sync-status sources (one `syncStatusKind` feed for both Settings tile and dashboard).

---

## 2. Performance ("laggy")

Measured: activity cold start 173–213 ms (`am start -W`) — fine. Flutter frame stats can't be captured on the release build (`gfxinfo` sees 0 frames; Flutter renders its own surface). To measure real jank next time: give the `profile` build type release signing in `android/app/build.gradle.kts` so `adb install -r` works without wiping data, then use DevTools timeline.

The dominant "lag" today IS finding #1 (open never completes). Beyond it, code-level jank sources, ranked:

| Cause | Where | Fix |
|---|---|---|
| Full-text index rebuilt with sequential SAF reads on the UI-visible open path | `tylog_core/src/search_index.dart:147` | Background + batch/parallelize reads; persist per-file fingerprints (already there — trust the cache) |
| Global `setState(() {})` on every workspace change rebuilds the whole 346-line `build()` | `lib/app_mobile.dart:257`, `:2836` | Scoped `ListenableBuilder`s per destination |
| Eager `for`-loop ListViews build all children (1373 articles!) | `app_mobile.dart:4639, 4673, 4554`; `knowledge_screen.dart:99, 134` | `ListView.builder` |
| Typst preview renders on the main thread | preview/split modes, `app_mobile.dart:2921, 2949` | Debounce render at 400 ms; move compile off UI thread if the package allows |
| 250 ms polling during sync + 25 s cloud poll always on | `app_mobile.dart:3563`, `workspace_controller.dart:291` | Event-driven progress; stop timers when idle/backgrounded |
| 4947-line `app_mobile.dart` | — | Split by destination (maintainability; also helps rebuild scoping) |

---

## 3. UX/UI heuristic audit (Nielsen + Fitts/Hick/Jakob/Miller/Doherty/Tesler)

Severity 4 = usability catastrophe … 1 = cosmetic. Merged findings from two independent passes over live screenshots.

| Sev | Screen | Violation | Finding → Fix |
|---|---|---|---|
| 4 | All main screens | Nielsen #1, #9 | Silent vault failure renders as cheerful empty states; user may conclude data is lost (and could "Delete vault" trying to fix it). → Error banner + Retry; distinct loading/skeleton state vs true-empty state. |
| 4 | Vault kebab menu | Fitts, error prevention | "Forget vault" and "Delete vault and files" are adjacent, same styling, no confirmation shown for Forget; Delete is permanent. → Divider + red destructive styling + typed/2-step confirm for Delete; rename to outcome language ("Disconnect, keep files" / "Delete permanently"). |
| 4 | SAF picker flow | Error prevention | No post-pick confirmation of what folder was chosen and what will happen — already produced a stray vault inside `Audiobooks/`. → Confirmation card: chosen path, whether it's an existing vault / empty / non-empty, then commit. |
| 3 | Settings vs Sync dashboard | Nielsen #1, consistency | "Sync: Not configured" vs configured Nextcloud on the next screen. → One status source. |
| 3 | Library | Nielsen #10, Hick | Sixth tab truncates to "En"; 6 flat tabs for content types adds choice load and hides tasks/notes behind taxonomy. → Scrollable labeled tabs short-term; unified list + filter chips long-term (see §4). |
| 3 | More sheet | Nielsen #6 | 9 items; **Settings is only reachable by scrolling** and invisible until you do. → Reorder (Settings up), or split "create" vs "view" vs "maintenance" actions. |
| 3 | Empty states | Nielsen #10 | No recovery affordance anywhere ("Check vault", "Retry"). → Action button in every empty state. |
| 2 | Vaults sheet / Settings | Jakob, match to world | Raw truncated `content://…` URIs as the only folder identity. → Human name + folder leaf, URI behind an expander. |
| 2 | Vaults sheet | Visibility | Active-vault radio is subtle; "Add or create vault" ambiguous. → Highlight active row; split "Add existing" / "Create new". |
| 2 | Today header | Recognition | Icon-only pencil/folder actions, no labels/tooltips. → Tooltips + semantics labels. |
| 2 | All | Doherty | With the open-stall, every navigation feels dead >400 ms with zero feedback. → Skeletons/spinners tied to real progress. |
| 1 | More sheet | Consistency | Menu item reads **"Typst help"** — typo ("Typst"). → Fix string (`app_mobile.dart:2787`). |
| 1 | Picker | Recognition | `_index`/`_system` internals visible in the folder picker; users may "clean them up". → README/`.nomedia`-style naming or docs; can't hide from SAF, but the confirm step (above) can explain. |

Done well (keep): explanation dialog before the SAF picker; icon+label pairs and Material structure in the More sheet; clear active-tab underline; journal-first launch screen; sync dashboard's diagnostics log + copy button.

---

## 4. PKMS-over-Typst — product-level suggestions

From a code-level pass of the interaction model vs Logseq/Obsidian conventions (your daily-driver patterns):

1. **Capture friction is the #1 product issue**: More → New page → title → template ≈ 4+ taps. Add a FAB (or long-press on Today) for instant blank capture; make templates opt-in, not a mandatory dialog (`app_mobile.dart:888-901`).
2. **Link syntax fights muscle memory**: links are `#tylog.ref-note("id")[Title]`; support `[[Title]]` sugar that expands under the hood and renders as a chip in the rich editor (`rich_editor.dart:1525`).
3. **Backlinks ("Context") are buried in the More sheet** and open as a modal, killing the read-note→see-links loop. Promote to a swipe-up panel or persistent editor toolbar button.
4. **Library's 6-tab taxonomy is imposed, not emergent** (Hick's law; Logseq/Obsidian use search+filters). A unified stream with kind/tag filter chips and a search field would collapse 6 destinations into 1 — and fixes the "En" truncation for free.
5. **Rich↔source mode switching loses undo history** (`rich_editor.dart:619-632`) and hides "protected blocks" without saying what they are. Announce protected content; keep undo across modes.
6. **Split mode is unusable on phones** (50/50 `Row`, `app_mobile.dart:2949-2967`): stack vertically under 600 dp or drop it on phones.
7. **700 ms autosave debounce** (`workspace_controller.dart:171`) exceeds the Doherty budget and risks losing the last keystrokes when Android kills the app; 400 ms + flush-on-pause (`WidgetsBindingObserver`).
8. **Typst's PDF-page preview vs reflowing text**: for reading on mobile, a reflowed rich render (what the rich editor already does) is the right default; keep PDF preview for export fidelity, not for everyday reading.
9. **Articles (1373 web clips) dominate the vault** but are second-class in the UI (one tab). Consider a read-later-style view (unread/favorites, reading progress) — that's the actual majority use of this vault.
10. **Magic/insert menu only exists in source/split modes** (`app_mobile.dart:3098-3106`); rich mode — the default — can't insert links/tasks via UI.

---

## 5. Suggested order of attack

1. Fix the open pipeline (§1 fixes 1–3) — restores the app + kills most perceived lag. **Do first.**
2. Error surfacing + destructive-action guards (§3 sev-4 rows) — trust and data safety.
3. Quick UX wins: Settings reachability, "Typst" typo, tab labels, status consistency — an afternoon.
4. Perf hygiene: ListView.builder ×5, scoped rebuilds, 400 ms debounce.
5. Product bets: quick-capture FAB, `[[wikilink]]` sugar, Context panel promotion, unified Library.

Screenshots and raw dumps from this audit: `~/.claude/jobs/3ac91331/tmp/` (01–24 PNG, semantics XML, pulled `index.json`).
