# Bounded subagent task cards

The coordinator supplies one card plus [delegation instructions](delegation.md). Status/dependencies/model are authoritative in [the tracker](plan.md). Paths below are repository-relative. They are entry points and an initial write scope; trace their callers before editing. Supporting files may be requested with a concrete reason. Existing tests/fixtures take precedence over new harnesses.

Each code task includes its smallest meaningful regression check. Reproduced audit probes should be moved/adapted into the normal suite by the owning task; the historical capture stays unchanged. For code-reviewed findings, first establish the failure at the real call site. If it cannot be reproduced, return the evidence and uncertainty instead of implementing a guessed fix.

## T00

**Capture phone baseline** — Device.

**Read/write entry points:** integration_test/vault_worker_jank_test.dart; integration_test/sync_attribution_test.dart; existing Sync diagnostics.

**Done when:** Record device/OS/build, vault file counts/bytes, network, first-usable-editor time, sync completion time, scan count and frame timings over 3 identical runs. Use an isolated representative vault. Retain traces without credentials or note bodies. If no device, keep WAITING_DEVICE; desktop timing cannot substitute.

## T01

**Verify and index the five existing probes** — All.

**Read/write entry points:** docs/audits/2026-09-06/reproduction_test.dart; reproduction-output.txt; existing test files.

**Done when:** Run normal tests once and the explicit audit probes. Record five expected failures by name and cause, separate harness failures. Map each probe to its destination regression test file. Keep intentionally failing probes outside default CI until their owning fix lands; reuse fixtures rather than create another harness.

## T02

**Settle active worker commands on shutdown** — F02.

**Read/write entry points:** lib/vault_worker.dart; test/vault_worker_test.dart.

**Done when:** The existing real-worker shutdown probe completes within 1 second with one terminal outcome. Double dispose is safe; commands after disposal fail promptly. Active controller scan unwinds. A newly spawned worker rebuild succeeds. Preserve single-flight behavior; a timeout alone is not a fix.

## T03

**Reindex a failed sync only after local content changes** — F01.

**Read/write entry points:** lib/nextcloud_sync.dart and its result/error boundaries; lib/workspace_controller.dart; test/nextcloud_sync_test.dart; test/workspace_controller_test.dart.

**Done when:** Two 401 failures before transfer produce zero added index publications. A run that downloads content then fails still refreshes that content once. Publish the sync error before awaiting maintenance. Carry actual local-change evidence across the failure path; keep existing conflict and deletion protections.

## T04

**Pause rejected credentials and back off transient retries** — F01.

**Read/write entry points:** lib/workspace_controller.dart polling and config updates; test/workspace_controller_test.dart.

**Done when:** Using fake time, 401/403 causes zero automatic retry attempts until credentials change or explicit retry; manual retry acts immediately. Transient delays increase from the existing polling interval to a documented cap and reset on success. Suggested policy: 25, 50, 100, 200, then 300 seconds; freeze the chosen values in the test and result note. Verify one in-flight attempt and no retry storm after resume.

## T05

**Run one necessary startup index pass** — F05.

**Read/write entry points:** lib/workspace_controller.dart openVault/syncNow; test/workspace_controller_test.dart.

**Done when:** Cold startup with transferred content publishes one index, not two. Cold startup with unchanged remote or pre-transfer failure still obtains one usable index. Warm startup remains usable during sync. Count passes using the existing probe; do not infer completion from a status string.

## T06

**Protect startup sync when backgrounded** — F10.

**Read/write entry points:** lib/workspace_controller.dart foreground trigger handling; integration_test/sync_foreground_native_test.dart.

**Done when:** Startup uses the existing foreground service with no duplicate concurrent ownership, including repeated lifecycle callbacks, and reliably stops it on completion/failure. Mock-channel checks pass. Native background/resume verification is recorded separately under T28; until then mark device validation pending.

## T07

**Make save success explicit** — F03.

**Read/write entry points:** lib/workspace_controller.dart save; lib/app_mobile.dart _save wrapper; test/workspace_controller_test.dart.

**Done when:** Save communicates success/failure to callers. Failed writes retain dirty state and the latest buffer; success marks only the saved revision. Cover a newer edit arriving during the write. Enumerate every save caller and preserve timer callback behavior; navigation changes belong to T08.

## T08

**Gate note and vault navigation on successful save** — F03.

**Read/write entry points:** lib/app_mobile.dart note/day/new-page navigation; lib/app_mobile/vault_lifecycle.dart; widget regression tests.

**Done when:** The existing failed-save navigation probe passes. Inject a storage error as well as the empty-note rejection: note/vault/buffer stay unchanged, dirty stays true, error is visible. Successful save allows navigation. Cover every path that replaces or closes the buffer, not only a single button.

## T09

**Prevent old vault operations publishing new-vault state** — F13.

**Read/write entry points:** lib/workspace_controller.dart open/close/sync/scan completion; test/workspace_controller_test.dart.

**Done when:** Gate old-vault I/O, select a new vault, then release the old operation. Old completion cannot change new source/index/status/conflicts/results or clear the new syncing flag. After the gated I/O returns, old resources and promises settle within 1 second in the controlled test. Cover both success and failure completion, plus close without replacement.

## T10

**Make the latest note selection win** — F13.

**Read/write entry points:** lib/app_mobile.dart _openNote and callers; widget navigation tests.

**Done when:** Delay open A, complete open B, then release A: B remains selected with its own source. Repeat across a vault change. Late callbacks after disposal do not call setState. Preserve save-failure behavior from T08.

## T11

**Establish one buffer-aware note mutation path** — F04.

**Read/write entry points:** lib/workspace_controller.dart note editing/persistence; lib/vault.dart if needed; focused controller tests.

**Done when:** For the open note, transform the latest buffer and retain intervening edits; later autosave does not revert the mutation. For a closed note, ordered read-modify-write persists changes. Two delayed edits to one path preserve both. Gate a mutation and save in both completion orders: preserve newer edits and avoid incorrectly clearing dirty state. Keep the API concrete; migrate callers in T12/T13/T14.

## T12

**Route task checkbox/status changes through the mutation path** — F04.

**Read/write entry points:** lib/app_mobile.dart _setTaskStatus; task/widget tests.

**Done when:** Task completion survives pending autosave and manual save for the open note. Closed-note task changes persist. Recurring occurrence completion stays correct; missing/ambiguous task IDs surface an error. One successful mutation requests one coalesced refresh.

## T13

**Route article status/relevance/rating through the mutation path** — F04.

**Read/write entry points:** lib/app_mobile.dart _setNoteProperty/_rateArticle; article/widget tests.

**Done when:** Each status, relevance and rating change survives a subsequent save; body edits are preserved. Verify open and closed notes and a write failure. Reuse T11; leave reindex-vs-cancel semantics to T16.

## T14

**Check bulk rewrite and conflict resolution against open edits** — F04.

**Read/write entry points:** lib/app_mobile.dart _runBulkRewrite; lib/workspace_controller.dart resolveConflict; relevant tests.

**Done when:** Reproduce each remaining direct writer against a dirty open note. Either preserve the latest edits through the mutation path or refuse safely with an actionable message; never silently replace them. Retain backups and explicit conflict choices. Record a green counterexample if a suspected path is already safe.

## T15

**Open a new page before background indexing** — F06.

**Read/write entry points:** lib/app_mobile.dart _newPage; widget tests.

**Done when:** Hold a background scan gate closed: after file creation, the new editor opens without releasing it. Repeated create taps cannot start duplicate in-flight creation. Save failure leaves the original editor intact; create failure is visible. Refresh occurs after successful creation.

## T16

**Refresh after rating/delete without cancelling indexing** — F07.

**Read/write entry points:** lib/app_mobile.dart _rateArticle/_deleteArticle; controller/widget tests.

**Done when:** While a scan is gated, rating/delete sends zero cancellation commands and queues at most one coalesced follow-up. After release, metadata reflects the change and deleted notes disappear. Cover failed deletion and the discard confirmation path.

## T17

**Keep saved searches current in storage and UI** — F08.

**Read/write entry points:** lib/app_mobile.dart _showKnowledge callbacks; lib/knowledge_screen.dart; saved-search/widget tests.

**Done when:** The existing two-save probe passes. Save A then B, delete A then B without closing Search: storage and chips match after each step. Reopening preserves the final list; failed persistence leaves the prior state visible with an error.

## T18

**Publish search readiness and revision after the index swap** — F09.

**Read/write entry points:** lib/vault_worker.dart search-build events; lib/workspace_controller.dart search state; worker/controller tests.

**Done when:** Readiness/revision changes only after the new search index answers queries. A failed/cancelled rebuild does not announce a ready replacement. Closing/switching clears or invalidates state. Old-vault events cannot publish readiness. Keep progress events independent.

## T19

**Refresh an open Search screen when its index changes** — F09.

**Read/write entry points:** lib/knowledge_screen.dart; lib/app_mobile.dart Search wiring; widget tests.

**Done when:** Open Search while indexing, release the search-build gate: current results update without typing/reopening. Loading and zero matches are distinguishable. A delayed old query cannot overwrite newer text/tag/status results; subscriptions are removed on dispose.

## T20

**Refresh assets for the current note revision** — F11.

**Read/write entry points:** lib/app_mobile.dart _loadNoteAssets/_insertAttachment; asset/widget tests.

**Done when:** Insert an image and switch to preview without reopening: the compiler file map contains its bytes. Release an old note asset read after a newer note load: no old assets contaminate the map. Removing/changing an image reference updates the map.

## T21

**Wait for current assets before sharing PDF** — F11.

**Read/write entry points:** lib/app_mobile.dart _sharePdf; integration_test/share_pdf_native_test.dart; focused tests.

**Done when:** Export waits for a gated current asset load and compiles the intended source/files. Missing assets produce a visible error. A note switch during export cannot mix the new note with the old filename. Existing native PDF-sharing checks remain passing when hardware is available.

## T22

**Define a bounded report dependency strategy** — F12.

**Read/write entry points:** lib/report.dart; packages/tylog_core/lib/src/report.dart; existing compiler VFS APIs; test/report_test.dart.

**Done when:** Return a short implementation contract identifying how generated reports reference notes, assets, bibliography and packages. Specify a fixture with transitive/static and dynamic imports. Prefer existing compiler file-resolution facilities; do not prune dependencies using an unproven regex. Specify the safe behavior for dependencies that cannot be resolved statically.

## T23

**Load report dependencies without unrelated vault media** — F12.

**Read/write entry points:** lib/report.dart; minimal report-flow changes in lib/app_mobile.dart; test/report_test.dart.

**Done when:** For the T22 fixture, unrelated files contribute zero readBytes calls; all required imports, bibliography and assets resolve. Check required content and import resolution against the baseline; compare page count only for deterministic fixtures with the same compiler/fonts. Handle dynamic dependencies according to the agreed contract, and show preparation/failure state. Record loaded bytes before/after.

## T24

**Make cancellation work after note scanning** — Cancellation risk.

**Read/write entry points:** packages/tylog_core/lib/src/maintenance.dart; validation/search loops only as needed; lib/vault_worker.dart; focused tests.

**Done when:** First gate validation/search and reproduce ignored cancellation. Cancellation at a stage boundary starts no later stage; mid-loop cancellation stops at the next documented safe checkpoint. Exactly one terminal event, no partial search-index publication, and the next rebuild succeeds. Bound completion after current I/O returns; do not pretend to cancel uninterruptible native I/O.

## T25

**Measure dashboard diagnostic reload overhead** — Dashboard risk.

**Read/write entry points:** lib/widgets/sync_dashboard.dart; lib/app_mobile.dart _loadSyncDashboard; existing diagnostics.

**Done when:** Observe 60 seconds with a populated unchanged trace: record storage read count/bytes, parsing time and frame impact. Separate status freshness from trace reloads. Deliver a measured conclusion and a bounded follow-up fix task if material; do not cache or redesign without evidence. Device-only measurements remain WAITING_DEVICE until available.

## T26

**Measure Android SAF contention** — SAF risk.

**Read/write entry points:** android/app/src/main/kotlin/org/tylog/tylog/SafBridge.kt; existing SAF integration tests.

**Done when:** Use an isolated vault: compare 30 note opens/saves with idle storage versus a large attachment transfer. Record p50/p95/max and lock/operation timing, plus content integrity. Deliver a measured conclusion and a bounded follow-up task if material. Preserve atomic replacement; do not alter the lock as an assumed optimization.

## T27

**Run integrated software regression gate** — All fixes.

**Read/write entry points:** test/; integration_test/; audit reproduction probes; analysis output.

**Done when:** All five historical probes now pass and equivalent regression tests run in the normal suite. Scoped analyze is clean; normal suite has no new failures/skips; 10k gate passes. Run a combined startup + failed sync + edit + navigation + refresh test. Record exact commands, counts, commit/diff fingerprint and logs; review any newly discovered failures.

## T28

**Verify the reported phone symptom and close the audit** — Device.

**Read/write entry points:** existing profile-build/device tests; Sync diagnostics; tracker evidence.

**Done when:** Repeat T00 on the same device/fixture/network for 3 runs. Cold startup has one necessary scan; 5 idle minutes after completion produce zero extra content scans; invalid credentials produce zero repeated auto-sync attempts; background/resume does not strand processing. Verify 30 opens/saves preserve content and native image/PDF actions. Report before/after timing and existing frame-test gates. Baseline-relative timing regression over 10% requires investigation, not silent acceptance; freeze exclusions before reruns.


## T29

**Expose canonical compiler file requests** — F12; split from T23 after T22 discovery.

**Read/write entry points:** packages/typst_flutter/rust/src/api/typst.rs; compiler.dart; generated bindings; focused native tests.

**Done when:** Native source/file lookups record canonical VFS paths, exposed via a take-and-clear compiler API. Static, relative, package and dynamically evaluated paths use the existing resolver. Tests verify recording, clearing and cache correctness after files are supplied for a retry. Existing compiler clients continue working; bindings regenerate successfully. T23 receives the exact API and validation evidence.

## T30

**Drain SAF replies before worker shutdown** — device-discovered blocker.

**Read/write entry points:** lib/app_mobile/vault_lifecycle.dart; lib/vault_worker.dart; focused worker tests; Android profile evidence.

**Done when:** First-time Android folder selection opens the selected vault exactly once. Disposing or replacing a worker immediately settles its client stream but leaves its isolate alive until an in-flight SAF/native await returns and cooperative cancellation reaches a terminal point. No platform response targets a killed Dart port. Focused worker tests pass, first-pick profile reproduction has no native crash or duplicate scan, and switching vaults during a gated rebuild remains usable.
