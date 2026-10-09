# TyLog v5 implementation status

Current version: see `pubspec.yaml`. Last reviewed: 2026-10-09.

## Implemented

- Clean schema-v5 vault with `daily`, `notes`, `projects`, `articles`, `assets`, `outputs`, `_system`, `_index`, and `.tylog`
- Namespaced `tylog` Typst interface; no raw wikilinks or durable tag/file/collection registries
- Rich note metadata, derived backlinks, tasks, dates, attachments, calendar entries, and compressed search index
- Today-first mobile workspace with Journal, Tasks, Library, Calendar, Search, and secondary graph (concept-map, focused, all-files, timeline, and Voronoi-treemap views)
- Selection-aware Magic actions for links, tags, tasks, dates, projects, citations, attachments, formatting, tables, equations, and reports
- Styled, tappable blocks by default, with exact Preview, Source, and responsive split views available explicitly
- Reproducible Typst reports and sibling PDF export
- Atomic note-file replacement and Nextcloud conflict/checksum/polling behavior retained with v5 sync allowlists; database projection errors preserve the file and require retry
- Focused local `typst_flutter` fork with explicit setup, CocoaPods/SwiftPM packaging, and no build-time downloads
- Standard iOS host for iPad validation while Android and macOS remain the release platforms
- Typed task creation and commands, three-language date suggestions, status glyphs and chips, shared rows, and Doing-controlled time tracking (0.11.9–0.12.0)
- Image blocks with size/alignment/move controls and crop preserving the original (0.11.7)
- Journal pages only, collapsed Agenda, upload-confirmation and complete-listing checks, and local sync safety copies (0.11.6)
- Headerless daily repair preserves text and takes an undo copy (0.11.8)

## Persistence and retrieval

Typst note files remain authoritative for note content. A successful file save is kept if the private SQLite projection/revision transaction fails; the app reports the error and retry repairs the projection. SQLite also holds annotations and search data and is not synced as a database file.

Revision transport uses session envelopes in `_system/revisions` through ordinary file sync. New unpublished local heads coalesce in fixed 60-second windows; materialized or uploaded revisions and conflict bases are sealed. Envelopes carry parent history for idempotent ancestry checks. Failed writes leave outbox work pending; this is not a separate v2 batch/device-head protocol.

Optional offline semantic search uses an explicitly downloaded multilingual-e5-small model. Generated answers remain out of scope.

## Deliberate limits

- Old-vault migration is unsupported
- Journal blocks hide Typst syntax until selected; arbitrary Typst stays exact and is edited one block at a time or in Source
- No Markdown storage (Markdown/Logseq/Obsidian sources are converted to Typst on import, never stored), HTML export, generated answers, collaboration, plugin system, Kanban, or Zotero integration

## Verification

```sh
flutter analyze
flutter test
flutter test integration_test/pkms_native_test.dart -d macos
flutter build apk --release
flutter build macos --release
flutter build linux
```

Earlier v5 verification: automated analysis, 66 tests, native macOS integration, Android release, macOS release, an iPad simulator launch, and Linux compilation have passed. The simulator check found and fixed a `ListTile`/`Material` assertion before release. Linux evidence is in [GitHub Actions run 28754170425](https://github.com/berlogabob/TypstSeq/actions/runs/28754170425). The implementation and remaining checks are tracked in [issue #42](https://github.com/berlogabob/TypstSeq/issues/42) under `status:check-needed`.

## Check needed

- 0.12.3 was checked on the A24 (2026-10-09, server unreachable): typed tasks, due, repeat set/clear, list chip edits, long-press status, mention popup, leave-app save (1.0–1.4 s, 8 of 8), sync failing in under a second. Not checked on a phone: image blocks, crop, Ctrl+Enter, conflict resolution, the P30.
- Audit status per finding: `docs/audits/2026-10-08-status.md`. Open: sync rereads all revision files, large downloads buffered in memory, uncached Library filtering, oversized functions, 8dp corners, shared confirm dialog/chips, 48dp calendar cells.
- An index or query version bump empties the Library while it rebuilds (7 min for 8,871 notes on the A24; a query bump took over 30). Keep the old index visible during a rebuild before bumping `kVaultQueryVersion`.
- Seen on the A24, not fixed: the list priority popup overlaps the bottom bar; the long-press status menu overlaps the row above and selects the glyph; the "validation errors=… warnings=…" pill after a rebuild is noise; "Continue reading" adds a row on Today.
- SAF writes rename the note away for a moment; hidden from the app by the storage lock, visible to outside readers. An in-place rewrite was rejected (a kill mid-write would leave a truncated note).
- Android autocomplete jumping/revert remains undiagnosed. Suspects: a late IME full-text update or a post-sync reload.
- A headerless daily went three hours without syncing on the A24; still needs device evidence. Automated checks cover SAF repair snapshots, timestamp change signals, and fresh-background/10-minute full scans.
- New unpublished local note heads coalesce within fixed 60-second windows; materialized/uploaded revisions and conflict bases remain immutable. Existing large histories are not shrunk, so their envelopes remain large.
- EmbeddingGemma phone trial at 256 dimensions before switching models.
- Deferred: image captions/figure, text wrap and anchors; task session-history view; converting imported checklists to tasks; quick-add date parsing.
- `wip/incremental-index` is parked; the macOS app is still on an old build.
