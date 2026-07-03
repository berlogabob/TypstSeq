# TyLog

Local-first Typst journal/PKM app inspired by Logseq, Obsidian, and org-mode.

Data model:
- user notes are plain `.typ` files
- daily notes live in `journal/YYYY-MM-DD.typ`
- pages live in `pages/Title.typ`
- `.tylog/index.json` is a rebuildable cache
- `.tylog/tylog.typ` is a small helper imported by notes

Implemented:
- daily journal
- plain Typst editor
- save/rebuild index
- wikilinks/backlinks
- graph view
- Typst-query PKMS metadata with legacy-note recovery
- full-text search, canonical tags, managed files, and validation problems
- templates and ordered PDF collections with Typst citations
- Typst preview via `typst_flutter`
- embedded Nextcloud WebDAV sync
- Android release APK + macOS debug build

Sample vault: `sample_vault/`
PKMS smoke fixture: `sample_vault/pkms_fixture/` (uses versioned `.tylog/tags.json` + `.tylog/files.json`)

PKMS metadata is edited from **Knowledge**. Notes remain plain `.typ` files;
tags, managed file records, templates, and collections are inspectable JSON/Typst
files. `.tylog/index.json` and `.tylog/search-index.json.gz` are disposable local
caches and are intentionally excluded from Nextcloud sync.

## Run

```sh
flutter test
flutter analyze
flutter run -d macos
flutter run -d XPH0219904001750
```

## Sync / Nextcloud workflow

Troubleshooting guide (wiki seed): `docs/wiki/Android-Near-Realtime-Sync-Troubleshooting.md`

On desktop TyLog now prefers a working Nextcloud folder:

1. `TYLOG_VAULT_DIR` when set.
2. `~/Nextcloud/TyLogVault` when `~/Nextcloud` exists.
3. First `~/Library/CloudStorage/*Nextcloud*/TyLogVault` on macOS.
4. App documents fallback.

Desktop workflow:
1. Keep notes as normal `.typ` files in `TyLogVault/`.
2. Safe to edit notes outside TyLog.
3. In TyLog, press `Rebuild index` after external edits.

Android status:
- tested: app-owned vault on real Android device
- embedded WebDAV sync is available through `Nextcloud` + `Sync`
- no Nextcloud side app is required

Conflict behavior:
- Nextcloud may create conflict copies if two devices edit same note.
- TyLog does not merge conflicts.
- Resolve by opening both `.typ` files in an editor and keeping the wanted text.

Safe to delete/regenerate:
- `.tylog/index.json` — safe, press `Rebuild index`
- `.tylog/search-index.json.gz` — safe, rebuilt from notes and registries

Do not delete unless you know why:
- `.tylog/tylog.typ` — helper macros for preview
- `journal/`, `pages/`, `assets/` — user data

## Release

- APK: https://github.com/berlogabob/TypstSeq/releases/download/v1.0.0%2B6/app-release.apk
- Release: https://github.com/berlogabob/TypstSeq/releases/tag/v1.0.0%2B6
- Pages: https://berlogabob.github.io/TypstSeq/

## Ponytail limits

Skipped Android folder picker and conflict UI. Add when app-owned WebDAV sync is not enough.
