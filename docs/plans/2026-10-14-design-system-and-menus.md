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
