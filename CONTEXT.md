# TyLog Knowledge Model

TyLog is a research logbook where notes, concepts, evidence, and arguments share one graph without losing the identity of external material or prior edits.

## Current status

Current version: see `pubspec.yaml`. Tasks are typed lines with four
statuses, editable chips and shared rows; Doing runs the timer. Image blocks
support sizing, alignment, moves and crop. Journal lists pages with a collapsed
Agenda. Sync confirms uploads from listings and keeps local safety copies;
headerless daily repair keeps existing text.

## Open work

- Phone verification of 0.11.6–0.12.0: sync loss fixes, mention lookup, image blocks, crop, task typing with a phone keyboard, and headerless-daily repair.
- Android autocomplete jumping/revert remains undiagnosed. Suspects: a late IME full-text update or a post-sync reload.
- A headerless daily went three hours without syncing on the A24; cause unknown.
- Large historical revision envelopes remain large; new unpublished local heads coalesce in fixed 60-second windows.
- EmbeddingGemma phone trial at 256 dimensions before switching models.
- Deferred: image captions/figure, text wrap and anchors; task session-history view; converting imported checklists to tasks; quick-add date parsing.
- `wip/incremental-index` is parked; the macOS app is still on an old build.

## Engineering rules

- Keep transient shell and graph status in overlays; use AnimatedSize only for docks that reserve space, and settle animations before tapping them.
- Default Flutter-test startup suppresses database and updater side effects; injected fixture vaults are supported.
- Keep macOS unsandboxed until persistent security-scoped bookmarks support folder access; App Store delivery needs that work.
- Measure CPU, exact bytes, and sync decisions before diagnosing hangs or lost text; external-vault claims require observations.
- Use root-isolate and Flutter frame timings for Flutter jank; gfxinfo decor counts do not establish it.
- Article producers preserve LLM links, use the auto-related marker, read gzip/plain indexes safely, and emit five-stage status.
- Bump the index version when parsing changes cached semantics.
- Normal profile installs preserve the production app only with its release keystore; isolate integration drive with the optional `.profiletest` suffix.
- Device editor replay includes cold startup and delayed save; report tooling failures instead of suppressing them.
- Improve existing mechanisms before changing formats, trace every consumer, and review delegated edits.
- Keep Room databases reachable in release builds and preserve the hidden macOS window lifecycle.
- Verify the packaged native library against the source build, beyond the setup stamp.
- Use the Node/Edge/Source/Revision vocabulary below and preserve original bytes and unknown properties during edits.
- Measure import, extraction, and embedding throughput separately; synthetic chunks do not establish extraction throughput.
- Record dated hardware, seven-day use, and publication evidence; DONE requires every acceptance item, WAIVED needs an explicit dated waiver, and P26 starts after P12 passes.
- Keep private source/query text, credentials, and raw corpus evidence out of Git unless explicitly redacted.
- Foreground the correct macOS window for runtime checks and distinguish fixture evidence from real-vault observations.
- Keep public methods on classes when splitting Dart files, use the existing State shim, and put part directives after imports and exports.
- Report results concisely in plain language and follow task-specific verdict limits.

Local gates: `test/rich_editor_test.dart`, `test/widget_test.dart`, `test/graph_test.dart`, `test/archive_release_test.dart`, `test/background_completion_test.dart`, and `test/release_config_test.dart`; device frame metrics: `integration_test/support/editor_frame_metrics.dart`. Human visual acceptance of Timeline Read and Maintenance remains separate. The active acceptance plan is `docs/plans/tylog-plus/plan.md`.

## Language

**Node**:
An addressable knowledge record with a stable identity and a type. Notes, concepts, claims, tasks, people, and works are node types.
_Avoid_: Page, block, graph mode

**Edge**:
An addressable typed relationship between two nodes. Its validity period describes the relationship, independently of when TyLog stored it.
_Avoid_: Link record, diagram line

**Source**:
External evidence with a stable identity, such as a document, book, article, recording, or dataset. Changes to its bytes create source versions without changing that identity.
_Avoid_: Attachment, note

**Revision**:
An immutable record of a change to an authoritative entity. Parent revisions express history and concurrency; wall-clock time does not choose a winner.
_Avoid_: Backup, autosave copy
