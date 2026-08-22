# Audit of the 0.4.x batch — findings and outcomes

Written 2026-08-22 after 0.4.2 shipped. A re-check found three misses; a
systematic adversarial audit of all 46 commits then found ~20 more, several
created by that week's own fixes interacting. Everything below is either fixed
with a test proven to fail on the previous code, or explicitly recorded as not
a bug.

## The four shapes

Every finding is an instance of one of these. They are worth knowing by name,
because each has now bitten more than once.

1. **A fix applied to some of N equivalent paths.** The vault is written by four
   contexts — UI isolate, worker isolate, Android background service, CLI — and
   a fix that lands in one is invisible in the others. Now structurally closed:
   the maintenance routine lives in `tylog_core`, and
   `test/maintenance_parity_test.dart` fails if any context writes a derived
   artifact itself.
2. **"Absent" read as "current".** A field that was never written defaults to
   today's value, so stale data claims to be fresh.
3. **A guard on the read side with no write-side counterpart**, so the thing it
   protects is laundered back in.
4. **A frozen value read as live.** A snapshot taken for one purpose — a
   listing, a conflict record, a cached hash — is later consulted as if it
   described the file now.

## Fixed

| # | Finding | Shape |
|---|---|---|
| P0-1 | "Keep Nextcloud's version" could **delete** the file it claimed to keep. A remote-deleted record keeps its snapshot as evidence; the dialog read it without checking `remoteExists`, so the deleted content was offered as a live side — and when it was a superset of local, the default preselected it with "loses nothing" while the resolve deleted the local file. | 3 |
| P0-2 | The **background service** still suspended the whole vault on one conflict — the gate removed from the foreground in 0.4.0. Self-perpetuating: the repairs that clear such a record all live inside `sync()`, behind the gate. | 1 |
| P0-3 | Self-heal compared **two frozen snapshots**, so it deleted live conflicts. Record written (local A / remote B), user edits to C, a peer uploads A → record deleted, C never uploaded, "Conflict resolved" on screen. Now compares the live file against the remote. | — |
| P0-4 | A bulk resolve decided each step by reading `syncError`, a slot shared with sync; and a not-ready config made `resolveConflict` return silently, so the batch reported "Resolved N" over an untouched vault. | — |
| P1-5 | `reusable` ignored `queryVersion` while the built index stamped it current, so a query-only bump reused every entry and exported laundered facts through the donor. Reuse is still allowed (the derived half is fine); the unvouchable facts are dropped. | 3 |
| P1-6 | A failed inspect kept metadata from the **old** bytes and stamped it with the new file's fingerprint and hash — permanently authoritative, and donated. | — |
| P1-7 | Donor prune and donor load asked different questions, so donors were kept forever and read never. | 1 |
| P1-8 | `IndexDonorStore.load` left `queryVersion` implicit. | 2 |
| P1-10 | A **failed save was discarded** if the user kept typing — edit gone, UI still showing a save pending. | — |
| P2-11 | The CLI rewrote both indexes unconditionally, and `tylog dedupe` scanned **with no inspector** while deciding which files to delete. | 1 |
| P2-12 | Only the UI swept orphaned temp files; the background service — the process most likely to be killed mid-write, and the reason the grace period exists — never did. | 1 |
| P2-13 | `_sweepSafBackups` and `pruneUnusable` wrapped their whole loop in one `catch`, so one locked file skipped everything after it, forever. | — |
| P2-14 | `IndexDonorStore.publish` swallowed every failure with no way to report it — the exact way the mechanism died silently for days before. | — |
| P2-15 | The search index had no derivation stamp, so a derive-only bump left search holding pre-fold tags forever. | 2 |
| P3 | Three tests asserted nothing: an anti-test that would pass with the feature deleted, a guard test with no positive control, and an assertion on a variable the test set itself. | — |

## Not a bug

Nothing remains here. Both entries that once did — the `sync_state.json`
absent-field default and the never-retried `fallback-inspected` marker — were
recorded as deliberate because the two obvious fixes were each worse than the
symptom. Reopening them found a third option in both cases, which is the lesson
worth keeping: "both fixes are worse" is a reason to look for a third, not a
reason to close the finding.

## Closed since

| # | Finding | Shape |
|---|---|---|
| F1 | A note the Typst inspector already failed on was **never retried**. The marker `fallback-inspected` was written to mean "try again" and nothing consumed it, so a wedged worker or a timeout under load was permanent until the note was edited or the index rebuilt by hand. Retrying them all would spend the whole budget on known-bad notes, so they get their own small slice of it: `maxFailedReinspectionsPerScan`. | 3 |
| F2 | A `sync_state.json` predating `schema`/`remoteKey` is trusted. Rejecting it discards a tested migration; treating it as recovered hands the user a comparison per file on their first sync after upgrading. So neither: the pass forces the rewrite, and the window is provably one pass wide. | 2 |
| D | The four contexts each held their own version of the post-change routine. Between them they skipped every step at least once — the search identity guard only in the worker, the orphan sweep only in the UI (the process *least* likely to be killed mid-write), the donor load only in the app, so the CLI published a donor every run and consumed none. Now one routine in `tylog_core`, pinned by a source scan with its own negative control. | 1 |
| F1b | The retry F1 added recompiled **six headerless dailies every scan forever**. Their query does not fail — it succeeds and finds nothing, because there is nothing to find, and both outcomes shared the marker `fallback-inspected`. Split: a query that threw or timed out is retried, one that succeeded over a headerless note is `no-metadata` and left alone. Found by shipping F1 to the A24 and reading what it actually retried. | 2 |
| I1 | The Logseq importer emitted a **Typst dictionary with repeated keys** — one imported daily carries `login` and `pswrd` eleven times each — so the note has not compiled since the import and every reader fell back to source parsing. Suffixed (`login-2`) rather than deduplicated: dropping the extras would delete ten of eleven credentials. | — |
| L | **`resolveConflict` took no lock** — the one operation that deliberately overwrites a side of a disagreement, and the only vault write with no arbitration against the background service. Under its own owner name, because the lock is re-entrant by owner and releasing it under `'ui'` would have handed a running sync's lock away. | — |

## Still open

Nothing. The remaining locking item from the earlier write-up — the cold rebuild
running unlocked — is now a decision rather than an oversight: it writes only
`_index/` (device-local, never synced) and this device's own donor (a per-device
path no peer writes), so concurrency there costs duplicate CPU and not
correctness. The `VaultSyncWorker` timeout strand is closed by the declared
deadline in the lock file.

## Verified on hardware

Both phones, after the batch:

| | P30 (Android 10) | A24 (Android 16) |
|---|---|---|
| Index | version 10, query 1 | version 10, query 1 |
| Typst-queried notes | 6,207 / 6,215 | 6,207 / 6,215 |
| Fallback parser | 8 (0.13%) | 8 (0.13%) — was 432/4,225 (10%) |
| Notes carrying re-derivation facts | 6,207 | 6,207 |
| Pending conflicts | 0 | 0 |

After this batch, on the A24: index version 10, query 1, 6,215 notes, 6,208
Typst-queried, zero conflicts, no crash, no leftovers, index and donor and
search index all rewritten in the right order on launch. The fallback count went
8 → 7 on the first scan under F1 — one note recovered from what had been a
permanent failure. Of the remaining seven, six are headerless dailies (F1b, not
failures at all) and one is the duplicate-key import (I1).

The A24 arrived on 0.4.2 with a v9 index, zero query facts, and a pending
conflict **on the donor file itself**. On launch it cleared that conflict
automatically, refetched the donor (`cache-refetched` in its trace), rebuilt to
version 10 by inheriting 6,207 sets of facts rather than recompiling, and
republished its own donor — in about four and a half minutes with one brief CPU
spike, against the fourteen minutes a from-scratch rebuild costs.
