# Task G: Logseq namespace titles -> part_of

Depends on Task A + D.

- One-off maintenance action (Settings > Maintenance, near existing repair actions) + same logic in the Logseq importer (packages/tylog_import_core/src/bin/logseq_import.rs and/or the Dart import path, whichever creates page titles): a page titled `A/B/C` gets title `C`, alias `A/B/C` added, `part_of` = id of page `A/B` (titled `B`, alias `A/B`), created if missing as kind `note`, recursively up to `A`. Existing pages matched by title or alias. Dry-run first: show list of changes, apply on confirm. Skip titles that look like URLs or dates (`/` inside `http`, `2026/2027`, `r/...`): require every segment non-empty and no `://`; show skipped ones in the dry-run.
- Real vault has e.g. `poplar bear/Проект/Мебель`, `Португалия/Налоги`, `Сплав/20220811`.
- Tests: pure planner function (titles -> changes), URL/date skip, idempotent second run, written headers compile.
- Done when tests pass, analyze clean. Do not commit. Report.
