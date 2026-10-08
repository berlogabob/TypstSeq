# TyLog v5 implementation status

Current release: 0.12.2+135. Last reviewed: 2026-10-08.

## Implemented

- Clean schema-v5 vault with `daily`, `notes`, `projects`, `articles`, `assets`, `outputs`, `_system`, `_index`, and `.tylog`
- Namespaced `tylog` Typst interface; no raw wikilinks or durable tag/file/collection registries
- Rich note metadata, derived backlinks, tasks, dates, attachments, calendar entries, and compressed search index
- Today-first mobile workspace with Journal, Tasks, Library, Calendar, Search, and secondary graph (concept-map, focused, all-files, timeline, and Voronoi-treemap views)
- Selection-aware Magic actions for links, tags, tasks, dates, projects, citations, attachments, formatting, tables, equations, and reports
- Styled, tappable blocks by default, with exact Preview, Source, and responsive split views available explicitly
- Reproducible Typst reports and sibling PDF export
- Existing atomic saves and Nextcloud conflict/checksum/polling behavior retained with v5 sync allowlists
- Focused local `typst_flutter` fork with explicit setup, CocoaPods/SwiftPM packaging, and no build-time downloads
- Standard iOS host for iPad validation while Android and macOS remain the release platforms
- Typed task creation and commands, three-language date suggestions, status glyphs and chips, shared rows, literal quick add, and Doing-controlled time tracking (0.11.9–0.12.0)
- Image blocks with size/alignment/move controls and crop preserving the original (0.11.7)
- Journal pages only, collapsed Agenda, upload-confirmation and complete-listing checks, and local sync safety copies (0.11.6)
- Headerless daily repair preserves text and takes an undo copy (0.11.8)

## Deliberate limits

- Old-vault migration is unsupported
- Journal blocks hide Typst syntax until selected; arbitrary Typst stays exact and is edited one block at a time or in Source
- No Markdown storage (Markdown/Logseq/Obsidian sources are converted to Typst on import, never stored), HTML export, SQLite, AI/RAG, collaboration, plugin system, Kanban, or Zotero integration

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

- Phone verification of 0.11.6–0.12.0: sync loss fixes, mention lookup, image blocks, crop, task typing with a phone keyboard, and headerless-daily repair.
- Android autocomplete jumping/revert remains undiagnosed. Suspects: a late IME full-text update or a post-sync reload.
- A headerless daily went three hours without syncing on the A24; still needs device evidence. Automated checks cover SAF repair snapshots, timestamp change signals, and fresh-background/10-minute full scans.
- New unpublished local note heads coalesce within fixed 60-second windows; materialized/uploaded revisions and conflict bases remain immutable. Existing large histories are not shrunk, so their envelopes remain large.
- EmbeddingGemma phone trial at 256 dimensions before switching models.
- Deferred: image captions/figure, text wrap and anchors; task session-history view; converting imported checklists to tasks; quick-add date parsing.
- `wip/incremental-index` is parked; the macOS app is still on an old build.
