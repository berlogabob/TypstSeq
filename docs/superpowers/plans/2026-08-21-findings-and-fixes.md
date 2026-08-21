# Findings from the 0.3.0+93 device rollout — scope of work

**Status:** 1a, 1c, 1d, 2 and all of 3 are **done** (2026-08-21, see §5).
1b remains. Originally scoped, not started. Written 2026-08-21 from the two-device rollout
(P30 / Android 10, A24 / Android 16) and the live vault with the article-pipeline
drain running. Sync-conflict findings are scoped separately in
`2026-08-21-sync-conflict-recovery.md`.

---

## 1. The shared index ("hard computing on the laptop") does not work — L

**Intent:** one machine does the expensive Typst inspection; every other device
reuses it via a donor index in `_system/index/<deviceId>.json`, matched by
content hash, so phones never recompile what the laptop already compiled.

**Reality, measured tonight:** both phones recompiled the entire vault from
scratch — P30 14.2 min for 5,086 notes, A24 4 min for 4,225 — while the Mac
contributed nothing. Three independent causes, each sufficient on its own:

**1a. The laptop does not produce an index at all.**
`pgrep` shows TyLog.app is not running on the Mac; its `_index/index.json` is
from Aug 20 06:58 and still plain JSON (pre-gzip, i.e. written by the old
build). Its donor is one of the four stale `indexVersion: 8, schema: 1` files
from Aug 19. Indexing lives in the app, but the machine doing the writing is the
Python drain, which never indexes. So the strongest CPU in the fleet does none
of the work and the weakest ones do all of it.
*Fix:* publish a donor from the CLI. `tylog index`
(`packages/tylog_core/bin/tylog.dart:49`) already scans with `CliTypstInspector`
and writes `_index/`, but it does **not** call the donor writer
(`_writeIndexDonor`, `lib/vault.dart:319`) — that lives app-side. Move donor
publication into tylog_core so the CLI emits one under a stable per-machine
deviceId, then run `tylog index` as the drain's post-step (it already chains
`build_digest.py`, so the hook exists).
*Exit metric:* after a drain batch, a phone's next scan reuses ≥95% of notes
from the Mac's donor and performs zero Typst compiles for them.

**1b. A schema bump invalidates every donor at once — including for changes
that did not touch the expensive part.**
The gate is `if (json['indexVersion'] != kVaultIndexVersion) continue;`
(`lib/vault.dart:466`). Today's v8→v9 bump was a *derivation* change (kind
aliased into tags); the Typst query output for every note was byte-identical.
Yet every donor died, so both phones recompiled thousands of notes to recompute
something they already had the inputs for. This is precisely when donor reuse
matters most, and precisely when it is guaranteed to fail.
*Fix:* store the raw queried metadata records in the donor (schema 4) alongside
the derived `NoteRef`, and split the version into `queryVersion` (bump only when
the Typst query itself changes) and `deriveVersion`. On a derive-only bump a
device re-derives from donor data instead of recompiling. Donor grows roughly
2×; measure before committing — if the size is unacceptable, store raw records
only for notes whose derivation is non-trivial.
*Exit metric:* simulate a derive-only bump on a 5k-note vault — zero Typst
compiles, index rebuilt from donors in under a minute.

**1c. Stale donors are never collected.**
Four dead v8/schema-1 donors (5.7 MB) plus two live v9 ones (13 MB) = ~19 MB
sitting in `_system/`, which is inside the sync allowlist, so **every device
downloads every donor forever**, most of them permanently unusable. Confirmed
present on both phones.
*Fix:* when writing its own donor, a device deletes donors whose
`indexVersion` is older than current, or untouched for 30 days.
*Exit metric:* after one index pass, `_system/index/` holds only current-version
donors.

**1d. The feature fails silently.** Nothing anywhere reports whether donor reuse
happened. It has been dead for at least two days and would have stayed dead
indefinitely — it only surfaced because it was asked about directly.
*Fix:* index completion reports "reused N notes from M devices, compiled K" in
the status line and the sync dashboard.

---

## 2. Notes referencing not-yet-synced assets fall back unnecessarily — S

A24 finished its rebuild with **432 of 4,225 notes on the fallback parser
(10%)** versus the P30's 18 (0.35%). Cause: the A24 is mid-sync, and a note
whose `#image("assets/…")` target has not arrived yet fails to compile, so its
metadata degrades to source parsing.

The 0.3.0+93 placeholder work substitutes a 1×1 image for assets **that exist in
the vault listing**. It does nothing for a *referenced but missing* path, which
is the case that actually matters on a syncing device.

*Fix:* resolve any unresolved image-extension path to the placeholder at compile
time rather than only substituting listed files — i.e. supply the placeholder
for the reference, not for the file. (Cheapest form: pre-seed the VFS with
placeholders for every image path referenced by the note being inspected.)
*Exit metric:* re-inspecting the A24 mid-sync yields fallback ≤1%, matching the
fully-synced P30. Guard: a genuinely broken note must still be reported as a
problem, not silently "fixed".

---

## 3. Housekeeping found in passing — S

- **Orphan temp files.** `.index.json.tylog-451878162009693.tmp` (P30, Jul 30)
  and `.sync_state.json.tylog-*.backup` survive in the vault; the atomic-write
  path leaves them behind on interrupted writes. Sweep them on vault open.
- **Drain junk gate misses redirect/404 pages.** All four remaining conflicts are
  scraper artefacts — three `docs.astral.sh - Redirecting`, one
  `coqui.ai - Site not found GitHub Pages`. These should never have become
  articles. Belongs to the article-pipeline repo (`junk_reason`), noted here
  because it is the source of the conflict churn in the other doc.
- **A stray keystroke creates a daily note.** A single character typed into the
  Today editor autosaved a 2-byte `daily/2026-08-20.typ` into the real vault
  before the empty-note guard engaged on deletion. The guard is right; consider
  not materialising a daily file until it has non-whitespace content.

---

## Ranking

1 is the one worth doing first and by a wide margin: it is the difference
between the laptop carrying the fleet and the phones each doing 4–14 minutes of
duplicated compute after every schema change. 1a alone (CLI publishes a donor,
drain runs it) recovers most of the value for a small change; 1b is what keeps
it working across future releases. 2 is a small fix with a visible quality
payoff on any syncing device. 3 is opportunistic.

---

## 4. Sync cost, measured on the P30 — 2026-08-21

Stage timings now ride in `sync_trace.jsonl` on every terminal event. First
real numbers, P30 / 11,610 files / a pass that transferred nothing (18.1 s):

| stage | ms | | stage | ms |
|---|---:|---|---|---:|
| scan-local | 9348 | | detect-renames | 366 |
| list-remote | 5590 | | load-local-state | 141 |
| prepare-remote-folder | 1180 | | **sync-file (all 11,610)** | **96** |
| probe-root | 778 | | save-local-state | 597 |

**This retired two planned optimisations before they were written.** Both
targeted the per-file loop — partitioning unchanged paths out of it, and making
the 5 s checkpoint O(changed). The loop is 96 ms of 18,100, and the checkpoint
never fires at all in a no-change pass because the loop it guards finishes in a
fiftieth of one interval. The "~1,440 checkpoint writes per pass" figure came
from reasoning about a 2-hour transferring pass and does not describe the
common case.

Fixed instead, from what the numbers actually showed:

- **The tree was walked twice.** The no-change shortcut takes a full recursive
  listing to compare mtime+size, discards it on any mismatch, and `scan-local`
  immediately re-walks the identical tree. Only a network PROPFIND separates
  them, so the snapshot is the same either way. One 9.3 s walk instead of two
  on every changed pass.
- **A guaranteed-405 MKCOL per run.** `prepare-remote-folder` ran *above* the
  shortcut, so every sync paid a round trip to be told the folder already
  exists. Moved below it, still above `list-remote` so a folder that really
  vanished is recreated on the full path.

Measured after: the no-change shortcut is **9.8 s, from 21–25 s** (load-state
183, probe-root 1154, scan-local-shortcut 8455), with no MKCOL at all.

### What is left, and it is one thing

`scan-local` is now **86% of a shortcut pass**. It is a single
`storage.list(recursive: true)`, but SafBridge answers it with one
`ContentResolver.query` per directory (`SafBridge.kt:471-513`), and nothing
caches it across calls — the indexer (`scanner.dart:417`), the validator
(`validation.dart:61`) and the backup sweep each walk the same tree again
afterwards. Options, cheapest first:

1. Share one listing between sync and the scan that follows it, invalidated on
   any local write. Bounded risk: a stale listing must never hide a file.
2. A `ContentObserver` on the tree URI so an unchanged vault skips the walk
   entirely. Bigger change, native side, and SAF's change notifications are not
   guaranteed granular — needs a fallback walk on a timer.

Not scheduled yet. Moving sync off the root isolate stays unscheduled for the
same reasons as before (conflicts, SAF tokens, the foreground service).


---

## 5. Closed 2026-08-21

| Item | Outcome |
|---|---|
| 1a laptop produces no index | Donor publication moved into tylog_core; `tylog index` emits one under a stable per-machine id, and the drain runs it as a post-step. |
| 1c stale donors never collected | `IndexDonorStore.pruneUnusable` runs on publish. |
| 1d fails silently | Index status reports "reused N from M devices" (`workspace_controller.dart`). |
| 2 unnecessary fallback on a syncing device | Placeholders now cover images a note *references* and the vault lacks, not just listed files. Proven against the real `typst` binary. |
| 3 orphan temp files | Swept at vault open after an hour untouched; the three on the P30's live vault are gone. |
| 3 drain junk gate | Fixed in article-pipeline (`junk_reason` + length floor). |
| 3 stray keystroke strands a daily | Emptying a file that was never a structured note deletes it; a real note still refuses. The old behaviour also left the editor permanently dirty, which disabled idle maintenance and midnight rollover. |

**1b (donors surviving a derive-only version bump) is the one left**, and it is
still the most valuable: today's v8→v9 bump changed only a derivation, yet every
donor died and both phones recompiled thousands of notes to recover data they
already had. Splitting `indexVersion` into `queryVersion` + `deriveVersion` and
storing raw queried records in the donor is unchanged as the plan.
