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
- Typst preview via `typst_flutter`
- Android + macOS debug builds

Sample vault: `sample_vault/`

## Run

```sh
flutter test
flutter analyze
flutter run -d macos
flutter run -d XPH0219904001750
```

## Sync / Nextcloud workflow

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

Do not delete unless you know why:
- `.tylog/tylog.typ` — helper macros for preview
- `journal/`, `pages/`, `assets/` — user data

## Ponytail limits

Skipped direct WebDAV and Android folder picker. Add only when Android must edit the same Nextcloud vault inside TyLog.
