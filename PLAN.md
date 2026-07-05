# TyLog v5 implementation status

Last reviewed: 2026-07-05

## Implemented

- Clean schema-v5 vault with `daily`, `notes`, `projects`, `articles`, `assets`, `outputs`, `_system`, `_index`, and `.tylog`
- Namespaced `tylog` Typst interface; no raw wikilinks or durable tag/file/collection registries
- Rich note metadata, derived backlinks, tasks, dates, attachments, calendar entries, and compressed search index
- Today-first mobile workspace with Journal, Tasks, Library, Calendar, Search, and secondary graph
- Selection-aware Magic actions for links, tags, tasks, dates, projects, citations, attachments, formatting, tables, equations, and reports
- Exact Preview, responsive split view, and controlled Normal blocks that preserve unsupported Typst byte-for-byte
- Reproducible Typst reports and sibling PDF export
- Existing atomic saves and Nextcloud conflict/checksum/polling behavior retained with v5 sync allowlists
- Focused local `typst_flutter` fork with explicit setup, CocoaPods/SwiftPM packaging, and no build-time downloads
- Standard iOS host for iPad validation while Android and macOS remain the release platforms

## Deliberate limits

- Old-vault migration is unsupported
- Normal mode edits only the documented controlled subset; arbitrary Typst remains exact in Preview/Source
- No Markdown storage, HTML export, SQLite, AI/RAG, collaboration, plugin system, Kanban, or Zotero integration

## Verification

```sh
flutter analyze
flutter test
flutter test integration_test/pkms_native_test.dart -d macos
flutter build apk --release
flutter build macos --release
flutter build linux
```

Automated analysis, 66 tests, native macOS integration, Android release, macOS release, an iPad simulator launch, and Linux compilation have passed. The simulator check found and fixed a `ListTile`/`Material` assertion before release. Linux evidence is in [GitHub Actions run 28754170425](https://github.com/berlogabob/TypstSeq/actions/runs/28754170425). The implementation and remaining checks are tracked in [issue #42](https://github.com/berlogabob/TypstSeq/issues/42) under `status:check-needed`.

## Check needed

- Run on the connected physical iPad after an Apple development certificate, team, device registration, and provisioning profile are configured. Simulator launch is the unsigned fallback.
- Exercise a real v5 Nextcloud folder from two devices, including conflict resolution and interrupted transfers.
- Review the Android Kotlin plugin deprecation warnings emitted by transitive plugins before the next Flutter toolchain makes them errors.
- Recheck Xcode device-service and `objective_c` code-asset warnings on the next macOS/Xcode toolchain update.
