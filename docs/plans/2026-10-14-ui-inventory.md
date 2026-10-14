# UI inventory (screen by screen, facts only)

Purpose: collect everything the app has on each screen, so menus, drawer and
settings can be redesigned as one system. Nothing here is a decision. "Seen"
lines come from the P30 (0.16.0+145 profile build); everything else is read
from the code. Line numbers are in `lib/` and drift.

Sections 1-6: bottom nav, More drawer, Settings. Sections 7-12 (below the
open questions): Today/Journal/Search, Library tabs, editor and menus, sheets
and dialogs, design tokens and icons, perf measurements.

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

## 7. Today, Journal, Search

Today = `TodayPage` (`work_surface.dart`) over the daily note; Journal = `JournalFeed` (lazy newest-first cards, one per daily note).

| Today (top to bottom) | Detail |
|---|---|
| AppBar | chevron prev day, title tap = calendar picker, chevron next day; Timestamped capture (`more_time`); Undo/Redo only for the plain long editor; View mode popup (Edit/Read/Preview/Source; icon follows mode); sync icon |
| Agenda | ExpansionTile: events (`event`), tasks (TaskRow), nested "Overdue · N", "All tasks →" |
| Continue reading | ExpansionTile (`history`) > Card > ListTile (`auto_stories_outlined`, progress bar) |
| Strips | IdeaHubStrip, ScreenshotStrip, then the editor |
| Floating | task clock pill (timer + stop) |

| Journal | Detail |
|---|---|
| AppBar | static date title, Timestamped capture, "Choose journal date" (`calendar_month`), sync icon; no chevrons, no view mode |
| Card per day | title (`titleLarge`), Agenda expansion, content read-only with TaskRows, "Start writing…" for empty days, "Write about this" (`edit_note`) on events |

| Search / Knowledge (route, not a sheet) | Detail |
|---|---|
| AppBar | "Search" or "Problems" title, Timestamped capture, popup "Knowledge sections" (Search / Problems, text only) |
| Search view | outlined field, saved-search InputChips, "Save" ActionChip, tag ChoiceChips, citations, results (TaskRow for tasks, ListTile with raw kind string as subtitle), hybrid keyword+vector order with no label |
| Problems view | grouped problem tiles with severity icon and fix buttons ("Convert", "Fix all N", "Triage", "Open files"), Triage route with checklist and "Create N pages" |

TaskRow (shared by Today, Journal, Search): leading status glyph (tap toggle, long-press menu), title, chip strip (priority, due, scheduled, repeat, elapsed).

## 8. Library (tabs: Notes, Articles, Screenshots, Tasks, Calendar, Audio)

| Tab | Controls | Row |
|---|---|---|
| Notes | kind FilterChips (no counts); create buttons only in the empty state | ListTile, kind icon |
| Articles | search field + sort popup + group popup; status ChoiceChips with counts; relevance chips; Import row; continue-reading card | ListTile + status chip + relevance chip + `more_vert` (delete) |
| Screenshots | same search/sort/group row (other group options, default group by source); status + category + relevance chips in a scrolling row | grid of cards, `more_vert` button, long-press sheet |
| Tasks | Open/Done/All chips, search icon toggling a borderless field, project dropdown | TaskRow, collapsible groups; no create |
| Calendar | MonthCalendar, "Open journal" row, ScreenshotStrip, items for the day | ListTile / TaskRow |
| Audio | Record + Import buttons | ListTile (alias or title, duration) |

Mismatches: search is a toggled icon (Tasks), an always-visible field (Articles, Screenshots), absent (Notes, Audio); filter chips are FilterChip / ChoiceChip in a Wrap / a scroller depending on the tab; "more" is a popup (Articles), an icon button (Screenshots), a long-press only (others); delete exists on two tabs; six different empty-state layouts; status vocabularies differ (articles: Unread/Skimmed/Read/Extracted/Cited; screenshots: Inbox/Kept/Acted/Archived); the filtered drill-down Library has five tabs (no Audio).

## 9. Editor, menus, reading, graph

| Surface | Contents |
|---|---|
| Rich editor dock (48 dp, shows on focus) | Undo, Redo, H1 (text) + heading menu, Bold, Italic, Strike, Underline, Mono, Highlight (long-press colours), Bullets, Numbers, Clear formatting, Insert (`add_circle_outline`) |
| Source dock | outlined buttons with text glyphs: = * _ $ # + |
| Magic sheet | 80% height grid: Insert (Note link, Mention, Tag, Date, Time, Citation, Attachment, Audio, Equation), Text style (6), Structure (Task, Project, Heading, Table, Report). Opened from the dock Insert button, or the "Magic" FAB (source/split only) |
| `/` palette, `@`, `[[` | popup list (all Magic actions except Task, `/todo`), mention and wiki-link suggestions |
| Modes | Edit, Read, Preview, Source via the AppBar "View mode" popup; Split only from More; reading mode has Back to edit, reading settings (font, night, fullscreen), Rate FAB |
| Context | full-screen dialog from More: path, Edit metadata, Outgoing, Linked files, On this day, Backlinks |
| Graph | AppBar popup (Concept map, Focused, All files, Timeline, Voronoi), chip row (legend FilterChips, orphans, hubs, export), canvas, selected-node bar |
| Note title area | no rename, no kind chip; kind only inside EntityHeader text; rename only via long-press on a reference chip |

Mismatches: the same menu is "Insert" (dock), "Magic" (FAB) and untitled; Split has no entry in the view chooser and shows the Edit icon; Task is in the Magic sheet but removed from the `/` palette; three chip types in the graph row; two undo/redo locations; Reading's "Back" always returns to Edit; "Discard article…" vs "Delete article?".

## 10. Sheets, dialogs, routes, notices

- Bottom sheets (about 18): drag handle on 14, missing on resolve-all, recorder, reading rating. Titles: `headlineSmall` (Vaults, Settings), `titleMedium` (screenshot actions), a ListTile title, or none.
- Dialogs (about 45): Cancel/primary on the right is common; dismiss label varies (Cancel, Close, Later, Done, Back to setup); primary label varies (Save, Create, Apply, Confirm, Delete, Open...); destructive styling differs (outlined error button in `showConfirmDialog`, plain TextButton for "Delete saved search", filled non-error "Delete permanently").
- Same decision, different container: choose-one-of-N is a sheet (duplicate owners, wikilink, Record/Import), a SimpleDialog (dialect, template) or an AlertDialog (module installed, Markdown duplicate); sync conflict is a full-screen route for one file and a sheet + confirm dialog for "resolve all".
- Routes: Knowledge, Sync dashboard, Triage, Library subset, Context (Dialog.fullscreen), Conflict (Dialog.fullscreen), PDF reader, Audio screen, Image crop.
- Notices: `showSnack` (about 80 uses) plus raw `ScaffoldMessenger` in three files; `MaterialBanner` with and without error colour; the status pill (progress, sync stage, retry) and task-clock pill.
- No first-run/onboarding screen besides vault-access dialogs.

## 11. Design tokens and icons as they exist

- Theme: Material 3, seed colour `0xFF0B2F44`, light surface override; no text/card/appbar/button/chip/dialog/snackbar themes. Dark theme lacks the hint colour override.
- Tokens (`widgets/constants.dart`): radii 6/12/20, spacing 4/8/12/16/24, tap target 48, editor inset 18, motion 150/200/260 ms. Usage: kSpace tokens appear in 46 of 117 EdgeInsets; raw values 6, 2, 22, 20, 18, 80, 64, 52, 32, 14, 10 exist; raw radius 8 (6 places); about 21 raw colours; font sizes 11/12 raw in graph and import; no icon-size token.
- Shared widgets and call counts: showSnack 81, showConfirmDialog 15, SettingsTile 13, LoadingIndicator 12, TaskRow 9, NotePickerSheet 9, PropertySelectChip 8, ProcessingPolicyEditor 2, statusPill (local closure) 3.
- Icons: 171 distinct. One meaning, several icons: edit (`edit_outlined`/`edit_note`), settings (`settings`/`settings_outlined`), overflow (`more_horiz`/`more_vert`), daily (`event_note`/`book_outlined`/`edit_note`), warning (`warning_amber`/`warning_amber_rounded`), screenshot, books/library (4 icons), close (`close`/`clear`). One icon, several meanings: `folder_open`, `create_new_folder`, `calendar_month`, `event`, `schedule`, `link`, `hub`, `sync`, `cloud_off_outlined` (3 sync states).

## 12. Measured: UI stalls during indexing and sync (A24, profile build)

| | Before | After |
|---|---|---|
| UI isolate stalls (>250 ms) per ~2 min of startup/sync | 10-12, up to 690 ms | 1 (678 ms) in ~195 s incl. a full index rebuild |
| Taps during index rebuild | not measured | 0.3-1.2 s to respond |

CPU profile of the UI isolate (45 s, cold start + sync): 18% in pure-Dart Unicode normalisation (`unorm_dart nfc`) called from `_loadSyncState` over every synced path, and a further ~20% decoding and validating the whole sync-state JSON on every poll tick. Fixed by an NFC fast path + cache (`nextcloud_sync/nfc.dart`) and a stat-keyed sync-state cache. Still visible, smaller: revision envelope decoding in `_syncNow` (~5%), continuous frame scheduling from progress spinners. Tools: `lib/diagnostics/jank_monitor.dart` (profile builds, logcat tag `flutter`, lines `TYLOG_JANK`), `tool/cpu_profile.dart` (VM-service CPU sampling of the main isolate).
