# Sync conflict recovery — scope of work

**Status:** scoped, not started. Written 2026-08-21 from a live incident on the
A24 (Android 16, release 0.3.0+93).

## Context — what actually happened

The A24 sat **695 articles behind for four hours** while the app was running and
the network was fine. Cause chain, each step verified on the device:

1. The article-pipeline drain rewrites `articles/*.typ` continuously. A device
   holding an older copy of a file the drain has since rewritten gets a
   `first-sync-different` / "both copies changed" conflict — even though nobody
   edited anything on the device.
2. **Any** pending conflict suspends automatic sync vault-wide
   (`Sync is paused until you review the conflicts`). Five junk conflicts —
   three `docs.astral.sh - Redirecting` stubs, one `coqui.ai - Site not found`,
   plus one real daily note — froze the entire device's sync.
3. Resolving one took **roughly ten minutes with zero feedback**. Tapping
   "Save resolution" closed the dialog and returned to a dashboard where the
   conflict was still listed, unchanged, for ten minutes — because
   `workspace.resolveConflict` (`lib/workspace_controller.dart:951`) does a
   WebDAV upload while a full sync saturates the link, then awaits
   `refreshIndex(always: true)`, i.e. the running scan plus one queued repeat.
   Nothing on screen says "resolving". Measured tonight: tap at 00:18, record
   gone and daily note correct at ~00:28. Indistinguishable from a dead button —
   during the investigation *I* concluded it had failed, and was wrong.
4. A latent trap sits behind that: `resolveConflict`
   (`lib/nextcloud_sync.dart:771`) re-probes the remote and throws
   `StateError('Nextcloud changed again; run sync and review the new conflict')`
   if the remote ETag moved since the record was written. It passed tonight, but
   on a vault with a live drain the remote moves constantly, and that error is
   caught into `syncError` — a banner whose dashboard slot is occupied by the
   "Syncing…" card, so it would never be seen.
5. Bonus: while a sync is in flight the dashboard's progress stream rebuilds the
   list continuously and swallows taps on conflict rows
   (`lib/widgets/sync_dashboard.dart:286` has no busy gate, so this is a
   hit-test race, not a guard).

Net effect: a class of conflicts that a user cannot resolve, blocking a sync
that has nothing to do with them, with no visible reason. This is the second
time the "resolving does nothing" symptom has appeared from a different cause —
see the comment at `sync_dashboard.dart:121`.

## Phase 1 — Stop unrelated conflicts freezing the vault — S

The single highest-value change: make the gate **per-path**, not global.

- Conflicted paths are skipped by the sync loop; every other path syncs
  normally. Files: `lib/nextcloud_sync/path_sync.dart` (the pass that currently
  bails), `lib/nextcloud_sync.dart` (gate check), status text in
  `lib/widgets/sync_dashboard.dart` / `syncStatusTitle`.
- Status line changes from "Sync is paused" to "N files need review — everything
  else is syncing".
- Exit metric: with one unresolved conflict pinned, a vault with 500 pending
  downloads syncs all 500; the conflicted path stays untouched. Regression test
  in `test/nextcloud_sync_test.dart` asserting the untouched-path count.

## Phase 2 — Auto-resolve the provably-lossless cases — M

Most conflicts here are not real disagreements. Resolve them without asking,
but only where no information can be lost:

1. **Identical content, different ETag/mtime.** Compare SHA-256 of both sides;
   equal → adopt remote cursor, drop the conflict. (The drain re-uploading a
   byte-identical file is a large share of tonight's five.)
2. **Fast-forward.** If one side's content is a strict prefix/superset of the
   other (append-only edit — exactly the `daily/2026-08-19.typ` case: remote 184
   bytes, local 294 bytes, identical up to the appended `== Reading` block),
   keep the longer side. Lossless by definition.
3. **Pipeline-authoritative articles.** A note carrying `import_sha256` (the
   producer contract in `spec/tylog-format-v1.md`) with no local user edits —
   local hash still equals the recorded import hash — takes the remote copy: the
   producer owns that file.
- Files: new `lib/nextcloud_sync/auto_resolve.dart`, called from the conflict
  recording path in `lib/nextcloud_sync/conflicts.dart`.
- Every auto-resolution is logged to `sync_trace.jsonl` with its rule name, and
  counted in the dashboard ("3 resolved automatically"). Never silent.
- Exit metric: replaying tonight's five conflict records auto-resolves at least
  four (three junk + the daily note by fast-forward); a genuine two-sided edit
  still stops for review. Unit tests per rule, fixtures from the real records.

## Phase 3 — Manual resolution that is honest about what it is doing — M

Two problems: it looks dead while it works, and it would look identical if it
actually failed.

**3a. Show the work (the one that bit tonight).** A resolve is a network upload
plus an index refresh — seconds to minutes on a busy vault. It must say so:
the row enters a "Resolving…" state with a spinner, and stays there until the
record is gone. Do not block the UI; do not await `refreshIndex` before
reporting success — the resolution is complete once the remote write and
snapshot cleanup land (`lib/nextcloud_sync.dart` end of `resolveConflict`), so
report then and let the index catch up in the background.
Files: `lib/widgets/sync_dashboard.dart` (row state),
`lib/workspace_controller.dart:951` (report before, not after, the refresh).
Exit metric: tapping Save shows progress within 200 ms and clears the row the
moment the record is deleted; a resolve on a busy vault never looks like a
no-op.

**3b. A conflict whose remote was deleted is permanently unresolvable.**
Proven on the A24 with `articles/coqui.ai - Site not found GitHub Pages.typ`:
the record was written at 17:00 with `remoteExists: true`; the file was later
deleted server-side (confirmed absent from the Nextcloud-client mirror, which
was live and current). From then on `resolveConflict`'s guard compares
`conflict.remoteExists (true)` against `currentRemote != null (false)` and
throws `Nextcloud changed again` on **every** attempt — while the only code
that could repair the record, `_refreshConflictRemote`, is reached only when
`remoteFile != null` (`lib/nextcloud_sync/path_sync.dart:280`). A deleted
remote therefore can never refresh, the conflict can never resolve, and it
gates auto-sync forever. The only escape tonight was deleting the record by
hand over adb.
*Fix:* in the sync loop, when a conflicted path's remote is **gone**, rewrite
the record to the delete-vs-changed shape (`remoteExists: false`) instead of
skipping it, so the existing "This device deleted / Nextcloud deleted" UI can
resolve it. Add a regression test that deletes the remote between recording
and resolving.

**3c. The ETag guard is right to exist; its failure mode is wrong.**

- On ETag mismatch, **refresh and re-decide instead of throwing**: re-probe,
  re-download the remote snapshot (`_refreshConflictRemote` already exists,
  `conflicts.dart:94`), then compare the new remote bytes with the ones the user
  was shown. Identical bytes → proceed with the chosen resolution. Genuinely
  different → re-present the dialog with the updated diff and a clear
  "Nextcloud changed while you were deciding" line.
- Bound the retry (2 attempts) so a pathologically hot file surfaces rather than
  spinning.
- Files: `lib/nextcloud_sync.dart:771` (the guard), `lib/app_mobile.dart:2130`
  (dialog re-present).
- Exit metric: resolving a conflict on a file the drain rewrites mid-decision
  succeeds when content is unchanged, and shows the new diff when it isn't —
  proven with a test that mutates the remote between probe and apply.

## Phase 4 — Never fail invisibly; resolve in bulk — S

- The error banner must not lose its slot to the "Syncing…" card: render
  `syncError` as its own element, and mark the failing conflict row with the
  reason inline. Files: `lib/widgets/sync_dashboard.dart`.
- Disable conflict rows while a sync pass is repainting the list, or debounce
  the progress notifier, so a tap either works or looks disabled — never a
  silent no-op. (Same failure class as `sync_dashboard.dart:121`.)
- **Resolve all** action: apply one choice (keep local / keep remote / run the
  Phase-2 rules) across every listed conflict, with a count confirmation.
- Exit metric: with 5 conflicts pending, one action clears them; a forced
  failure shows a visible reason on the row.

## Sequencing

Phase 1 first — it alone would have prevented tonight's four-hour stall. Phase 2
removes most conflicts before a human ever sees them. Phase 3 makes the
remainder resolvable. Phase 4 is polish on top, but the invisible-failure half
is a data-safety concern, so it ships with Phase 3 rather than after.

## Verification

Fixture-driven: the five real conflict records from tonight are checked in
(`test/fixtures/sync_conflicts/2026-08-21/`) and every phase replays them.
Device gate unchanged from the repo norm — release build, real vault, both the
P30 and A24, since this is a sync path and SAF/Android-version differences are
exactly where it bites.
