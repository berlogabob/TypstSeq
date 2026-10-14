# UI inventory (screen by screen, facts only)

Purpose: collect everything the app has on each screen, so menus, drawer and
settings can be redesigned as one system. Nothing here is a decision. "Seen"
lines come from the P30 (0.16.0+145 profile build); everything else is read
from the code. Line numbers are in `lib/` and drift.

Order of work: 1 More drawer, 2 Settings (this file), then Today, Journal,
Library (each tab), Search/Knowledge, note editor (toolbar, Magic menu,
`/` palette), audio screen, Vaults, Sync dashboard, Problems, Graph/Split/Context.

## 1. Bottom navigation (`app_mobile.dart` ~5455, rail on wide screens)

| # | Label | Opens |
|---|---|---|
| 0 | Today | today page |
| 1 | Journal | journal feed |
| 2 | Library | tabs: Notes, Articles, Screenshots, Tasks, Calendar, Audio (6th only when the audio shelf is wired) |
| 3 | Search | Knowledge sheet, search view (no-op without a vault) |
| 4 | More | the drawer below (does not change the selected destination) |

## 2. More drawer (`_showMoreMenu`, `_ShellAction`)

All 14 entries are always shown (no platform / vault conditions). Flat list of
ListTiles; one divider and a "Maintenance" label split it.

| # | Label | Icon | Does |
|---|---|---|---|
| 1 | Vaults | folder_outlined | vaults sheet |
| 2 | Settings | settings | settings sheet |
| 3 | New page | note_add_outlined | create page |
| 4 | New entity | person_add_alt | create entity |
| 5 | Audio | graphic_eq | jumps to Library > Audio tab (not a screen of its own) |
| 6 | Graph | account_tree_outlined | graph mode |
| 7 | Split editor | vertical_split | split mode on the current note |
| 8 | Context | link | full-screen dialog with backlinks / links panel |
| 9 | Share as PDF | ios_share | compile + share the open note |
| – | **Maintenance** (label) | | |
| 10 | Problems | warning_amber | Knowledge sheet, problems view |
| 11 | Rebuild index | refresh | full index rebuild |
| 12 | Relink vault | auto_fix_high | relink flow |
| 13 | Semantic search | manage_search | model download / search sheet |
| 14 | Typst help | help_outline | help dialog |

Seen: the sheet needs two scroll screens on the phone; items 1-9 are one
undifferentiated block mixing app-level (Vaults, Settings), create (New page,
New entity), views (Audio, Graph, Split, Context) and an output (Share).

## 3. Settings sheet (`widgets/settings_sheet.dart`)

Order as shown; "style" is the widget family, which is where the visual split is.

| # | Item | Control | Style | Condition |
|---|---|---|---|---|
| 1 | Appearance (Auto / Light / Dark) | 3 ChoiceChips beside a label | custom row | always |
| 2 | PDF page size | dropdown A4 / Letter / A5 / Legal | bare ListTile | always |
| 3 | Calendars ("My classes · Lab schedule") | opens a 7-field dialog | **card tile** | callback present |
| 4 | Audio: transcribe and translate | header; Transcribe automatically (checkbox); Translate automatically (checkbox); language chips + Add language; When: Only when I ask / Right after it is added / On schedule (radio) + "Every day at HH:MM"; helper text; Process now | **flat list** | vault open |
| 5 | Screenshots (OCR) | header; same three radios; status line; Process now | **flat list** | always shown; radios disabled off macOS, Process now still enabled |
| 6 | Local folder | path, no action | card tile | always |
| 7 | Vaults | opens vaults sheet | card tile | always |
| 8 | Sync | status, opens sync dashboard | card tile | always |
| 9 | Task reminders | asks notification permission | card tile | always |
| 10 | Migrate entity types | maintenance action | card tile | always |
| 11 | Clean up imported notes | maintenance action | card tile | always |
| 12 | Import Logseq/Obsidian vault | import flow | card tile | always |
| 13 | Install module | pack install flow | card tile | always |
| 14 | App version | version string, no action | card tile | always |
| 15 | Check for updates | opens GitHub release check | card tile | macOS only |

Seen: "Appearance" label wraps into three short lines beside the chips; card
tiles and flat lists alternate; Local folder and App version look tappable but
are not; the audio block (14 controls) is the tallest thing in the sheet and
sits between Calendars and Screenshots.

## 4. Same thing in more than one place

| Action | Where |
|---|---|
| Audio | More > Audio; Library > Audio tab |
| Vaults | More > Vaults; Settings > Vaults |
| Sync dashboard | AppBar sync icon; Settings > Sync |
| New page / New entity | More; Library > Notes buttons |
| Tasks | Library > Tasks; Today "all tasks" |
| Graph | More > Graph; AppBar popup while in graph mode |
| Knowledge / Problems | More > Problems; Search destination (same sheet, other view) |
| Check for updates | Settings tile (macOS); silent timer |

## 5. Mismatches visible in the code and on screen

- Enum and label names differ: `backlinks` is "Context"; `semantic` is "Semantic search" but lives under Maintenance, which the code comment defines as disruptive operations.
- Maintenance is split: Rebuild index and Relink vault (More) vs Migrate entity types and Clean up imported notes (Settings).
- Three different visual systems in one sheet: custom chip row, card tiles, flat checkbox/radio lists.
- Audio block order: switches and languages first, then the "when" choice, then the helper text; the screenshots block has only the "when" choice.
- Two titles for one section ("Audio transcription" while loading, "Audio: transcribe and translate" after).
- Settings copy refers to "the audio screen"; More > Audio opens a Library tab.
- Disabled-state rules differ: screenshot radios disabled off macOS, its Process now not.

## 6. Open questions for the redesign (to answer after all screens are collected)

- What belongs in the drawer: navigation, creation, current-note actions, or only things you reach rarely?
- Which of Vaults / Sync / Audio deserve one entry point only?
- One settings structure (sections, one tile style) vs. today's mix.
- Where do one-off maintenance tools (rebuild, relink, migrate, clean up, import, install module) live, together?
