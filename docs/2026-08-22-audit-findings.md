# Audit of the 0.4.x batch — findings and outcomes

Written 2026-08-22 after 0.4.2 shipped. A re-check found three misses; a
systematic adversarial audit of all 46 commits then found ~20 more, several
created by that week's own fixes interacting. Everything below is either fixed
with a test proven to fail on the previous code, or explicitly recorded as not
a bug.

## The three shapes

Every finding is an instance of one of these. They are worth knowing by name,
because each has now bitten more than once.

1. **A fix applied to some of N equivalent paths.** The vault is written by four
   contexts — UI isolate, worker isolate, Android background service, CLI — and
   a fix that lands in one is invisible in the others.
2. **"Absent" read as "current".** A field that was never written defaults to
   today's value, so stale data claims to be fresh.
3. **A guard on the read side with no write-side counterpart**, so the thing it
   protects is laundered back in.

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

**`sync_state.json` reads absent `schema`/`remoteKey` as current.** Flagged as
shape 2, and it looks exactly like one. Both safe-looking fixes are worse:
rejecting the file discards a deliberate, tested migration, and accepting it as
*recovered* hands the user a conflict per file on their first sync after
upgrading. The risk is also not real — an unbound cursor carries a
server-generated etag, so against a different server it simply fails to match
and the pass re-decides correctly. Recorded in the code at the check itself.

## Still open

- **Locking is inconsistent.** The worker isolate writes the index, the donor
  and the search index under no `VaultLock`; the UI holds it only across
  `syncNow`; `resolveConflict` holds none. Separately, a `VaultSyncWorker`
  timeout destroys the engine without Dart's `finally`, stranding the lock for
  up to the 10-minute stale window — and a rebuild longer than that lets the UI
  barge in mid-run. Pre-existing, bounded, and needs a heartbeat rather than a
  one-line change.
- **`fallback-inspected` notes are never retried** on unchanged bytes. This is
  deliberate — retrying known-bad notes would spend the whole inspection budget
  every scan — but it means a transient engine failure is sticky until the next
  edit or a forced rebuild.

## Verified on hardware

Both phones, after the batch:

| | P30 (Android 10) | A24 (Android 16) |
|---|---|---|
| Index | version 10, query 1 | version 10, query 1 |
| Typst-queried notes | 6,207 / 6,215 | 6,207 / 6,215 |
| Fallback parser | 8 (0.13%) | 8 (0.13%) — was 432/4,225 (10%) |
| Notes carrying re-derivation facts | 6,207 | 6,207 |
| Pending conflicts | 0 | 0 |

The A24 arrived on 0.4.2 with a v9 index, zero query facts, and a pending
conflict **on the donor file itself**. On launch it cleared that conflict
automatically, refetched the donor (`cache-refetched` in its trace), rebuilt to
version 10 by inheriting 6,207 sets of facts rather than recompiling, and
republished its own donor — in about four and a half minutes with one brief CPU
spike, against the fourteen minutes a from-scratch rebuild costs.
