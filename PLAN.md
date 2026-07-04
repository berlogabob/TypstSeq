# TyLog project status

Last reviewed: 2026-07-04 · app version `1.0.0+23`

## Implemented

- Plain-file Typst vaults with daily notes, pages, templates, and assets
- Safe temporary-file saves and 700 ms autosave
- Multiple local vaults with switching, forgetting, and guarded permanent deletion
- Typst source editing and native preview
- Stable note IDs, metadata, wikilinks, aliases, tags, backlinks, and file references
- Incremental index and compressed full-text search cache
- Local graph with accessible selection and large-vault neighborhood limiting
- Canonical tag and file registries, validation, legacy-header migration, and collection PDF export
- Embedded Nextcloud WebDAV sync, background polling, sync traces, and interactive conflict resolution
- Android release, macOS/Linux targets, and a lightweight web landing page

## Source-of-truth model

User content is stored in `journal/`, `pages/`, `assets/`, and versioned registry files under `.tylog/`. The files `.tylog/index.json` and `.tylog/search-index.json.gz` are derived caches and may be rebuilt.

## Deferred intentionally

- Rich-text/WYSIWYG editing
- Plugin and AI systems
- Realtime collaboration or automatic text merging
- A full browser application
- Encrypted credential storage

Add these only when a concrete user requirement justifies their maintenance cost.

## Verification

```sh
flutter analyze
flutter test
flutter test integration_test/pkms_native_test.dart -d macos
```

Release automation lives in `Makefile`. `make release` bumps the build number, runs analysis and tests, packages GitHub Pages, builds the Android APK, commits, tags, pushes, and creates a GitHub release when `gh` is authenticated.

See [USER_MANUAL.md](USER_MANUAL.md) for the complete product handbook.

