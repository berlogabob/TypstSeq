# Existing-feature reliability audit — 2026-09-06

Audited release **0.4.4+99**, commit **bacbf11**. Scope: existing features, navigation, save, sync/indexing, search, task/article controls, attachments and export. No production changes were made.

**Most relevant to the reported first-open delay and recurring processing/indexing:** failed sync attempts unconditionally reindex the vault; cold startup runs two indexing passes; shutting down an active index worker leaves its caller waiting indefinitely. The first two were reproduced with controlled storage/network boundaries; the third was reproduced with the real worker isolate. These are confirmed defects in this checkout, but attributing the phone's incident to one requires its trace and installed version.

No Android device was connected. This is a code and automated-behavior audit, not a completed device interaction or frame-time audit. It cannot establish that every button works on every platform or enumerate every possible bug.

## Verification

| Check | Result |
|---|---|
| `flutter test --reporter expanded` | 563 passed; one optional benchmark skipped |
| `flutter analyze lib test integration_test` | No issues |
| `TYLOG_RUN_10K_BENCHMARK=1 flutter test test/pkms_10k_benchmark_test.dart --reporter expanded` | Passed; entire test about 5 seconds. Includes the existing warm-scan and search latency assertions. Local filesystem/source parsing, not Android SAF/native Typst profiling. |
| `flutter test docs/audits/2026-09-06/reproduction_test.dart --reporter expanded` | Five intentional failures exposing the defects below; about 2 seconds |
| Whole-repository `flutter analyze` | 1,144 diagnostics, including unresolved `package:test/test.dart` in the separate core package. App/test/integration analysis is clean; do not interpret this package-resolution cascade as 1,144 application defects. |

The [reproduction probes](reproduction_test.dart) use temporary or in-memory vaults and a loopback WebDAV server. They assert desired behavior and intentionally fail on the audited release. They are outside the default test directory so the normal suite remains usable. [Captured output](reproduction-output.txt).

## Findings

P1 = prioritize because it can lose changes or block a core workflow. P2 = fix next. “Reproduced” means a runnable check exercised the real application method or worker. “Code-confirmed” means the control/data flow is present, but the complete interaction was not reproduced on hardware.

### F01 — P1 — Failed sync repeatedly reindexes unchanged content — reproduced

**Trigger:** an automatic poll reaches an unavailable/rejected Nextcloud connection. `pollIsUnchanged()` returns false on failure, and `pollTick()` attempts a full sync. The `syncNow()` error handler then unconditionally awaits `refreshIndex(always: true)`, even when authentication failed before any downloads. Polling continues every 25 seconds without failure backoff or an authentication pause.

**Evidence:** two loopback HTTP 401 poll attempts caused two additional index publications. The test expected zero. The error is only assigned after that scan, so the user can keep seeing processing before the actionable login error appears.

**Fix:** report the error immediately; reindex only if the failed run actually changed local content. Back off transient failures and stop automatic authentication retries until credentials change or the user retries.

Locations: [pollTick](../../../lib/workspace_controller.dart#L757), [sync error handler](../../../lib/workspace_controller.dart#L1015), [poll preflight](../../../lib/nextcloud_sync.dart#L298).

### F02 — P1 — Stopping an active worker leaves indexing awaiting a result forever — reproduced

**Trigger:** switch/close the vault during indexing. `VaultWorkerClient.dispose()` kills the isolate and closes its receive ports and relay. `run()` completes its output stream only when a terminal event arrives; it has no relay `onDone` handler, and shutdown does not send a terminal event to the active operation.

**Evidence:** start a real worker command, immediately dispose it, await the command: it never completes within the one-second test bound. At controller level `_scan` cannot reach its `finally`, leaving `_indexing`/`_activeScan` stranded. A subsequent vault rebuild can take the “already indexing” branch instead of starting work.

**Fix:** complete/fail every outstanding command when disposing or losing the worker, and let the controller unwind before reusing its scan state.

Locations: [worker run](../../../lib/vault_worker.dart#L417), [worker disposal](../../../lib/vault_worker.dart#L487), [scan lifecycle](../../../lib/workspace_controller.dart#L501).

### F03 — P1 — Navigation discards the buffer after a save failure — reproduced

**Trigger:** edit a note, encounter a rejected save, then open another note. `save()` catches the failure and returns normally. `_openNote()` proceeds without checking success and `replaceNote()` clears dirty state. Vault switching follows the same save-and-continue pattern.

**Evidence:** clearing a managed note caused the real `Vault.saveNote()` rejection; navigating to another note still succeeded and left `dirty=false`. The attempted edit was no longer in the editor. Storage failures follow the same catch path.

**Fix:** make save success explicit and require it before replacing/closing the editor buffer. Keep the current note and expose the error on failure.

Locations: [save](../../../lib/workspace_controller.dart#L415), [open note](../../../lib/app_mobile.dart#L717), [switch vault](../../../lib/app_mobile/vault_lifecycle.dart#L107).

### F04 — P1 — Task and article controls write behind the open editor — code-confirmed

`_setTaskStatus`, `_setNoteProperty`, and `_rateArticle` read from disk, write a replacement, and reindex. They do not reconcile that replacement with `workspace.source` when the edited file is already open. A later editor save can overwrite a completed checkbox, status, relevance, or rating with the old buffer; a pending autosave can do so immediately. Reindexing updates metadata, not the open source buffer. Bulk rewrites and conflict resolution also need this open-buffer audit.

**Fix:** route mutations of the open note through its current buffer and revision handling. Use one ordered read-modify-write path for closed notes. The reading-log action already demonstrates an open-buffer-aware approach.

Locations: [task status](../../../lib/app_mobile.dart#L1278), [note property](../../../lib/app_mobile.dart#L1312), [rating](../../../lib/app_mobile.dart#L2061), [existing reading-log handling](../../../lib/app_mobile.dart#L1972).

### F05 — P2 — Cold startup performs two complete index passes — reproduced


When the first sync transfers content, `syncNow()` already awaits `_scan()`. Separately, cold `openVault()` attaches `firstSync.whenComplete(() => rebuildIndex(force: false))`. Once sync and its scan finish, startup starts another scan, including downstream validation/search work.

**Evidence:** one cold startup produced two task-reconciliation/index-publication events, not one. This is duplicate work, not proof of an infinite loop. The second pass may reuse caches, but still traverses the maintenance pipeline.

**Fix:** have startup request an index only if the completed sync did not already produce the needed index.

Locations: [cold startup continuation](../../../lib/workspace_controller.dart#L393), [sync indexing](../../../lib/workspace_controller.dart#L966).

### F06 — P1 — New page waits for the whole vault before opening — code-confirmed

`_newPage()` creates the file, awaits `refreshIndex(always: true)`, and only then opens it. If another scan is active, `_scan()` queues a repeat and waits for both. A simple create button can therefore wait through minutes of unrelated work even though its new file exists. There is no local pending state preventing repeated creation attempts.

**Fix:** open the successfully created file immediately; update the index asynchronously. `_openLink()` already uses this ordering.

Location: [new page](../../../lib/app_mobile.dart#L859).

### F07 — P2 — Rating/deleting during indexing cancels the scan instead of refreshing — code-confirmed

`_rateArticle()` and `_deleteArticle()` call `_rebuildIndex()`. The controller treats a rebuild request during an active scan as a cancellation and returns immediately. The changed rating/deletion may remain stale in the UI, and the prior indexing work is discarded without these callers scheduling a replacement.

**Fix:** use the coalesced `refreshIndex(always: true)` mutation path. Reserve cancellation for an explicit cancel action.

Locations: [rating/deletion callers](../../../lib/app_mobile.dart#L2037), [rebuild cancellation branch](../../../lib/workspace_controller.dart#L470).

### F08 — P2 — Saved searches overwrite each other and the chips stay stale — reproduced

The Search route captures `savedSearches` once. Each save derives its new list from that original snapshot; delete does the same. The screen does not replace its displayed list after either operation.

**Evidence:** invoke the actual Search route's save callback for “First”, then “Second”. Storage contains only “Second”. Deleting multiple presets from the same route can similarly restore a previously deleted preset.

**Fix:** maintain and update the current preset list after successful writes, and render that same current list.

Locations: [Search callbacks](../../../lib/app_mobile.dart#L1037), [preset rendering](../../../lib/knowledge_screen.dart#L233).

### F09 — P2 — Search can remain empty/stale after indexing completes — code-confirmed

The worker starts with an empty search index and replaces it after the maintenance search-build stage. `KnowledgeScreen` requests results on initial mount and user query/filter changes, but does not subscribe to search readiness/index changes. Mutating the shared `VaultIndex` is insufficient: `_results` is a separate list and the open route does not automatically rerun its query.

**Trigger:** open Search during the initial build, or search immediately after an edit. The build can finish while the screen continues showing its earlier results until another input change or reopening.

**Fix:** expose search readiness/revision and rerun the current query when the searchable index changes. Distinguish “index still loading” from “no matches”.

Locations: [worker search state](../../../lib/vault_worker.dart#L197), [search replacement](../../../lib/vault_worker.dart#L292), [query triggers](../../../lib/knowledge_screen.dart#L129).

### F10 — P2 — Startup sync lacks the offscreen protection granted to manual/resume sync — code-confirmed; device validation needed

The app launches with trigger `startup`, but `keepRunningOffscreen` only includes `setup`, `manual`, `retry`, and `resume`. Backgrounding during the first-open sync therefore lacks this foreground-service protection. A subsequent resume sees an already-running sync and cannot start a replacement. Actual suspension depends on Android version/power management.

**Fix:** give startup the same continuation policy as other user-visible long syncs, or implement an explicit, tested pause/handoff.

Locations: [startup trigger](../../../lib/app_mobile/vault_lifecycle.dart#L80), [foreground trigger set](../../../lib/workspace_controller.dart#L871).

### F11 — P2 — Inserted images are missing from the immediate preview/PDF file map — code-confirmed

`_insertAttachment()` writes the image and inserts its source through `_applyMagic()`. That flow does not refresh `_noteAssetFiles`. Assets load only through `_loadSource()`, while preview/PDF compilation takes assets from `_typstFiles()`. A newly inserted image can therefore fail preview/export until the note is reloaded. A rapid export after opening an image-heavy note also races the unawaited asset load. Concurrent note opens have no generation guard around the shared asset map.

**Fix:** refresh the asset map when image references change and await the relevant load before exporting. Publish asset loads only for the note/revision that requested them.

Locations: [asset loading](../../../lib/app_mobile.dart#L457), [source loading](../../../lib/app_mobile.dart#L539), [attachment insertion](../../../lib/app_mobile.dart#L3009), [PDF share](../../../lib/app_mobile.dart#L2863).

### F12 — P2 — Creating a report reads almost the entire vault into memory — code-confirmed; timing unmeasured

`exportReportPdfStorage()` recursively lists the vault and reads every file except the explicitly excluded cache/temp areas. This includes unrelated attachments and existing exported PDFs, regardless of the selected report filter. Large media vaults pay for all these reads and hold their bytes before compilation; SAF and large attachments can make this operation particularly expensive.

**Fix:** construct the compiler file map from the report's selected notes and transitive dependencies. Show progress/error state while preparing and compiling it.

Locations: [report export](../../../lib/report.dart#L64), [report button flow](../../../lib/app_mobile.dart#L3039).

### F13 — P1 — Old async operations can publish into a newly selected vault — code-confirmed

`openVault()`/`close()` stop timers and the worker, but do not cancel or invalidate an in-flight `syncNow()`. That sync captures its old vault, later writes controller-level conflict/status/result fields, and unconditionally resets `syncing` in `finally`. Similarly `_openNote()` has no generation check after its save/read awaits. Slow operations from a previous selection can overwrite the state of a newer selection. F02 is a separate, reproducible shutdown-stream problem that makes switching even more fragile.

**Fix:** tie operations to a vault/navigation generation, drop stale results, and finish or cancel the old work before handing ownership to another vault. Add a delayed-I/O switch test.

Locations: [open vault](../../../lib/workspace_controller.dart#L271), [sync completion](../../../lib/workspace_controller.dart#L986), [note navigation](../../../lib/app_mobile.dart#L717).

## Performance/interaction risks needing measurement

- **Sync dashboard repeatedly reads and parses diagnostics.** It reloads every 500 ms; its loader rereads the trace file through storage and JSON-decodes its lines on the UI isolate. Single-flight protection prevents overlap, but not repeated work. Measure with a populated trace and SAF; use the existing progress notifier and cache unchanged diagnostics if this is significant. Locations: `lib/widgets/sync_dashboard.dart:95`, `lib/app_mobile.dart:2094`.
- **Late-stage cancellation is ineffective.** Cancellation is checked in the scanner, but validation and search building do not consult it. Pressing cancel after note scanning finishes can leave the expensive search-build stage running. Verify with a delayed search build, then add cancellation checks at stage boundaries and inside long loops. Locations: `packages/tylog_core/lib/src/maintenance.dart:224`, `lib/vault_worker.dart:209`.
- **Android reads and writes still contend on a vault-wide lock.** Moving indexing to an isolate does not eliminate SAF storage contention: each mutation holds the write lock for the whole operation. Large asset writes can delay note reads/saves. Measure operation duration before changing locking; preserve atomic file replacement. Location: `android/app/src/main/kotlin/org/tylog/tylog/SafBridge.kt:317`.

## What is already protected

Do not reintroduce or “fix” historical defects that are already addressed here: worker-side indexing/search, sync progress separated from whole-screen notifications, canonicalized etags, index-donor/reading-file transfers excluded from content-triggered scans, debounced journal arrows, and per-path conflict handling are present. The normal suite and 10k benchmark pass. The former donor-driven indexing loop is not established as a current defect by this audit.

## Recommended order

1. Fix F01, F02 and F05 together with the reproduction checks: eliminate avoidable scans and guarantee scan completion/cancellation.
2. Fix F03, F04 and F13 before further UI work: preserve user edits and vault ownership.
3. Decouple New page from indexing; repair rating/delete refresh semantics and Search's current-state handling.
4. Address startup backgrounding and attachment/export paths, then measure the dashboard and SAF contention on the affected phone.

For device attribution, capture the installed app version and Sync → Copy diagnostics after the symptom. Compare `started`/`completed`/`failed`, trigger, stage timings, transferred counts, and index publications. Then run the existing `integration_test/vault_worker_jank_test.dart` and sync attribution tests against an isolated representative vault in a **profile** build. No production vault was accessed or altered in this audit.
