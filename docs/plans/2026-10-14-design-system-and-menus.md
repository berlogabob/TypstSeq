# Design system, More drawer and Settings (decisions, 2026-10-14)

Inputs: `2026-10-14-ui-inventory.md`. Decisions made by Claude from the mismatch list; GUI confirmed by the user before any release.

## Rules (one design system)
- One tile style everywhere (`AppTile`: leading icon, title, optional subtitle, optional trailing, tappable only if it does something). Read-only facts (Local folder, App version) render as plain info rows, not tiles.
- One section style (`AppSection`: small header label, tiles below, divider between sections).
- One sheet frame (`AppSheet`: drag handle, `titleLarge` title, scroll body, safe-area).
- Tokens only: spacing kSpace*, radii kRadius*, new `kIcon` (20/24) and no raw numbers in new code.
- One icon per meaning (settings = `settings_outlined`, more = `more_horiz`, close = `close`, warning = `warning_amber_rounded`).
- Destructive actions: error-coloured filled button in confirm dialogs; dismiss label "Cancel".

## More drawer (fits one screen, no maintenance)
1. Switch: Vaults, Settings.
2. Create: New page, New entity.
3. This note (only when a note is open): Split editor, Context, Share as PDF.
4. Views: Graph.
Removed from More: Audio (Library > Audio tab already), Problems/Rebuild/Relink/Semantic search/Typst help (moved to Settings > Tools).

## Settings sections (order)
- General: Appearance (own full-width row, no wrapping label), PDF page size, Calendars, Task reminders.
- AI and processing: Audio (preset, servers, quality, when, languages), Screenshots.
- Storage and sync: Local folder (info), Vaults, Sync.
- Tools: Problems, Rebuild index, Relink vault, Migrate entity types, Clean up imported notes, Import vault, Install module, Semantic search.
- About: App version (info), Check for updates (macOS), Typst help.

## Slices
D1 (this one): `lib/widgets/ds/` components + tokens, More drawer, Settings restructure. D2: Library tabs (shared search/filter/empty-state). D3: dialogs and sheets (frame, labels, destructive). D4: icons sweep.

## D2: Library tabs (decisions)
- `LibraryToolbar` (lib/widgets/ds): always-visible compact search field with clear button; optional trailing sort and group popups (`more_horiz`-free, icons `sort`, `view_agenda_outlined`); optional single-row horizontal chip scroller (ChoiceChip, optional count) below. Same paddings (kSpace16 sides, kSpace8 between rows) on every tab.
- `AppEmptyState` (lib/widgets/ds): icon, title, one-line hint, optional primary/secondary buttons; replaces the six empty layouts.
- Search on every tab: Notes (title), Tasks (always visible instead of the toggled icon), Audio (title/alias), Articles, Screenshots. Same behaviour: case-insensitive substring over the visible fields; clear button.
- Row actions: trailing `more_horiz` popup wherever a row has actions (Articles: delete; Screenshots: existing actions; Notes/Tasks/Audio keep tap and long-press only). Existing long-press stays.
- Chip rows: one component, one scroller; Notes kind chips show counts.
- Status vocabularies stay per domain (articles and screenshots are different pipelines).

## D3: dialogs, sheets, notices (decisions)
- Bottom sheets: every `showModalBottomSheet` uses the `AppSheet` frame (drag handle, one title style `titleLarge`, safe area, scroll). No sheet without a handle (resolve-all, recorder, reading rating included). Sheet-internal titles use the same style.
- Dialogs with a dismiss + a primary action: dismiss is always labelled "Cancel" and sits left of the primary; informational one-button dialogs say "Close". "Later", "Back to setup" etc. only where the meaning is not cancel (keep and list them).
- Destructive confirmations all go through `showConfirmDialog` (error-coloured filled primary, verb names the action: "Delete", "Discard"); replace the plain TextButton / filled non-error variants.
- Notices: raw `ScaffoldMessenger.of(...).showSnackBar` calls go through `showSnack`; MaterialBanners share one helper with the error colour passed explicitly.
- Choose-one-of-N stays as-is (sheet for lists, dialog for 2-3 options); no new component.
## D4: icon sweep (decisions)
One icon per meaning (map in `lib/widgets/app_icons.dart`: edit, settings, overflow, close, warning, daily, sync states); replace duplicate variants; resolve the "one icon, several meanings" cases (`folder_open`, `calendar_month`, `sync`, `cloud_off_outlined`) by giving each meaning its own icon. Pure rename/sweep, no layout change.

## D5: screens and editor menus (decisions)
1. The Magic/Insert sheet is "Add to note" (sheet title, dock button tooltip, FAB label); its groups stay Insert / Text style / Structure (no duplicate "Insert").
2. Editor dock: the add button is the first dock item (always visible), then undo/redo, headings, formats.
3. View-mode popup gets Split (icon `vertical_split`, icon follows mode); the More > Split entry is removed (one place).
4. `/` palette includes Task (`/task`, `/todo` stays as alias).
5. Search result subtitles show a human kind label (Note, Article, Task, Entity...) instead of the raw kind string.
6. Graph chip row uses one chip style (FilterChip) for legend, orphans, hubs; export stays an icon button.
7. "Discard article…" and "Delete article?" become one wording: "Delete article".
Not in D5: Journal chevrons (feed has no single day), reading-mode return rule (needs product decision).

## D6: component themes and tokens (decisions)
Goal: tokenisation, not redesign; the app must look the same except where raw values disagreed. 
- `ThemeData` gets component themes built from tokens: card, dialog, chip, filled/outlined/text button shapes, app bar (no scroll tint), snack bar (floating), bottom sheet (top radius kRadiusLarge), input decoration (outline radius kRadiusMedium), list tile (horizontal kSpace16), divider.
- Dark theme gets the same hint colour override as light.
- Raw `Color(0x...)` in widgets move to `colorScheme` roles or named constants in `constants.dart`, except data-driven colours (graph legend, highlight palette, user-chosen).
- Raw font sizes (11/12) use `textTheme.labelSmall/bodySmall`; raw radius 8 uses kRadius tokens; raw paddings near token values (4/8/12/16/24) use kSpace tokens (leave odd values with a comment only if they are optical corrections).

## Open: Incoming sheet wording (to think through, 2026-11-08, nothing to build yet)
User did not understand two things on the phone's Incoming sheet.
- [ ] Cluster proposal row "Merge ai-assistant + tech-software → tech-software". It means two tag clusters (graph topics) became one at the last recount; Accept/Reject only changes `_system/clusters/snapshot.json`, never notes or tags. The row says neither "topic/cluster" nor what changes. Idea: "Topics ai-assistant and tech-software merged → keep one topic tech-software?" + 3-4 tags per topic. Same for rename/split rows. (`lib/app_mobile/enrich_flow.dart:934`)
- [ ] Enrich "Mentions" `#tag` chips. These are tags the worker extracted from the day's text. Desktop writes them into the day header when the day closes; Android shows them without writing (`_enrichAutoWrite` false). Chips only offer × (= reject forever), no accept, no "already applied / pending" state, and "Mentions" mixes them with entity links (link / ? / +). Decide: separate "Suggested tags" row, explicit accept, state shown. (`lib/widgets/enrich_review.dart:94`)

## Open: entity properties in one place (to think through, 2026-11-08)
Today aliases/part_of/properties are edited in three places (More > aliases, header "+", Part of chips). User wants one.
- [ ] Logseq-style `key:: value` lines at the top of an entity page = source of truth for properties (`Alias:: Fernando Marson, Marson, FM`, `Work:: IADE`, `Linked:: ...`). Scanner already parses legacy `tags::`/`source::`/`journal-day::` (`packages/tylog_core/lib/src/scanner.dart:1641-1708`), extend to any key.
- [ ] Open question: keep the header `properties:` dict as the stored form (lines folded into it on save) or keep the lines in the body only. Header = compiles and indexes cheaply; body lines = what the user types.
- [ ] Rendering: collapsible properties block (collapsed = header chip row as now, expanded = key/value table + raw lines editable). "+" in header adds a line to the same block, so both paths write one thing.
- [ ] Value resolving: a value matching an entity title/alias becomes a link (`Work:: IADE` -> part_of/link), reuse the enrich resolver; known keys map to fields (alias -> aliases, part of -> part_of).
- [ ] Memory link (enrichment thesis): properties = long-term facts; journal mentions = short-term; enrich worker proposes property lines into Incoming instead of writing.
- [ ] "Fill info" button on entity pages: per-kind template (place: type, address, period, status, hours, ticket, link; sections Кратко / История / Посещение / Источники), worker fetches + drafts, user accepts via Incoming. First manual run 2026-11-08 on 4 places from the 2026-11-07 trip.
- [ ] Evidence 2026-11-08 (P30, Castle of Montemor-o-Velho): with 2 aliases + kind tag + Part of/Contains + 5 property rows the header card fills the whole screen; body starts below the fold. Default collapsed: title + kind + one chip row (aliases/part_of count), properties table only when expanded; remember state per kind or per page.

## Open: entry barrier / whole-app UX review (2026-11-08, think first, nothing to build yet)
Product rule from the user: a plain user just writes the journal and everything else appears "by itself". The engine for this exists (enrich mentions -> entities/links, tag clusters, part_of, Incoming review). What is not ready is the surface: results are shown with internal terms, confirmation UI is unclear, entity pages/boards expose every concept at once. Also: mention extraction needs the LLM worker (Studio/Mac); a user with only the phone gets clusters and links but no mentions. Needs a whole-app system + UI/UX review, then simplify and remove.
- [ ] Board "Tree" view: user never understands what it shows (it is the part_of tree under the entity). On a page with no children it shows a single card, so it looks broken. Either explain (empty state "Nothing is part of X yet") or hide Tree until there are children.
- [ ] Tree card shows raw Typst header (`id: "2026...", title: "..."`) as the preview text instead of the body. Bug.
- [ ] Kanban: no visible way to add a task or a status/column from inside the board, and unclear how tasks get onto a board from outside. Needs an "Add task" in each column and a clear rule shown on the empty board.
- [ ] Entity header fills the screen (see properties section above).
- [ ] Incoming wording (see Incoming section above).
- [ ] Method: run app-audit (Maestro) on the P30 profiletest build with the real-vault copy; list every concept a new user meets in the first 5 minutes; cut or hide what the journal-first flow does not need.

## Open: logic vs UI separation (question, 2026-11-08)
Measured: `packages/tylog_core` (pure Dart, 0 Flutter imports, ~12k lines) holds parsing, index, writers, clusters, tasks. `lib/` (~69k lines) is the Flutter app, but 19 files there write to vault storage directly, including UI files (`app_mobile.dart` 7.1k lines, `app_mobile/enrich_flow.dart` buttons write decisions/run-requests, `widgets/whiteboard.dart`). `workspace_controller.dart` (3.8k) is a controller, not a widget, so it is testable without UI.
- [ ] Rule to adopt: widgets call a controller/service method; no `storage.writeText` in widget or flow files. Move enrich decisions, cluster accept/reject, whiteboard save into core or a controller, test them without `pumpWidget`.
