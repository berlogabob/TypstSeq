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

Current MVP uses the app-owned vault folder. This proves the file format, editor, graph, backlinks, and preview before adding folder-picker complexity.

Desktop workflow:
1. Put a TyLog vault inside a Nextcloud-synced folder.
2. Keep notes as normal `.typ` files.
3. Safe to edit notes outside TyLog.
4. In TyLog, press `Rebuild index` after external edits.

Android status:
- tested: app-owned vault on real Android device
- not added yet: Android Storage Access Framework folder picker
- therefore Nextcloud folder sync on Android is documented as pending, not claimed working

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

Skipped direct WebDAV and Android folder picker. Add only after local file vault is boringly useful and Nextcloud sync is the real blocker.
