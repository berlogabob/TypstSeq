# Settings as pages — design

Date: 2026-10-21. Approved in chat by the user (navigation "list, then pages"; grouping; scope labels; screenshot catch-up).

## Goal
Settings stops being one long bottom sheet. It opens a short home page of groups; each group opens its own page; the AI group has subpages. Same features, easier to find, and every setting says which devices it applies to.

## Structure
Home (full page, back arrow), one row per group with a one-line summary of its state:

| Group | Summary example | Contents |
|---|---|---|
| General | Auto · A4 · reminders on | Appearance, PDF page size, Task reminders |
| Calendars | 2 calendars | the calendar list (today's sheet, as a page) |
| AI | Studio · local first | subpages: Servers · Audio (transcription, translation, languages) · Articles · Screenshots (model, schedule, folder) |
| Sync and storage | Synced 11:05 · 2 vaults | Local folder, Vaults, Sync |
| Maintenance | 1 problem | Problems, Rebuild index, Relink vault, Migrate entity types, Clean up imported notes, Import vault, Modules, Semantic search |
| About | 0.19.3 | App version, Check for updates, Typst help |

Scope labels: a small line under a setting's title when it is not shared by all devices: "This device" (appearance, PDF size, reminders, local folder) or "This Mac" (screenshot folder). Shared settings (calendars, AI servers and tasks, screenshot schedule) carry no label.

Screenshot schedule: "Right after it is added" installs the on-the-fly watcher plus the nightly catch-up at the chosen time (mode `both`); "On schedule" = nightly only; "Only when I ask" = off. The page shows which one the Mac runs.

## Build
- `lib/widgets/settings/`: `settings_home.dart`, `general_page.dart`, `ai_page.dart`, `ai_servers_page.dart`, `ai_audio_page.dart`, `ai_articles_page.dart`, `ai_screenshots_page.dart`, `sync_storage_page.dart`, `maintenance_page.dart`, `about_page.dart`, `scope_note.dart`, `settings_actions.dart`.
- `SettingsActions`: one object carrying the values and callbacks `SettingsSheet` receives today (built once in `app_mobile.dart`); every page reads it.
- Pages reuse existing widgets (`AiConnectionsSection`, `ScreenshotsSettings`, calendar list, Sync dashboard entry). `AudioProcessingSettings` is split by a `section` parameter (audio / articles / screenshots model) rather than rewritten.
- Opening: More → Settings and the Mac menu push `SettingsHome` with `Navigator`; system Back works on every level. `SettingsSheet` is removed after its content moved.

## Out of scope
Two-pane Settings on wide screens, search in Settings, changes to what a setting does (except the screenshot catch-up rule above).

## Testing
- Walk test: open Settings, visit every page, find every setting listed above (nothing lost in the move).
- Existing settings tests move with their widgets (settings_sections, screenshots, audio widgets, AI connections, calendars).
- Screenshot mapping: "Right after it is added" -> `both`.
- Design tokens test; P30 check of navigation and Back; Mac check.
