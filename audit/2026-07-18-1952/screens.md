# Screens crawled — TyLog 0.1.0+65 (commit ec99ac2)

Driven 2026-07-18. Two targets, coordinate/screenshot-driven (the Flutter **release build
exposes no accessibility tree**, so neither Maestro nor macOS AX could enumerate widgets —
navigation was scripted from the nav map by pixel coordinates).

- **macOS desktop** (`macos`, window 745×928pt @2x): real vault `~/Nextcloud/TyLogVault`,
  fully populated (~1698 notes, 1676 articles). Driven via Swift CGEvent clicker + `screencapture`.
- **Android** (`XPH0219904001750`, ELE L29, Android 10, 1080×2340): vault re-granted at
  first run (reinstall had wiped `vaults.json`). The granted folder is an **empty
  `/storage/emulated/0/Download/TyLog`**, not the synced Nextcloud vault → Android surfaces
  are almost entirely empty-state. Driven via `adb input tap` + `screencap`.

Hierarchy dumps: only `hierarchy/android/01-today-launch.json` exists and contains **SystemUI
only** (no Flutter semantics) — so tap-target sizing from hierarchy is unavailable on both
platforms; measurements are image-based only.

## macOS (`screens/macos/`)

| Screen | Reached via | File |
|---|---|---|
| Today (populated: Agenda, Continue reading, today's note, Reading) | launch | 01-launch.png |
| Journal feed (day cards Jul 18/17/16) | nav → Journal | 02-journal.png |
| Library / Notes (5 notes) | nav → Library | 03-library-notes.png |
| Library / Projects (2) | inner tab | 04-library-projects.png |
| Library / Articles (All·1676, filter chips, status pills) | inner tab | 05-library-articles.png |
| Library / Tasks (checkable) | inner tab | 06-library-tasks.png |
| Library / Entities (**empty state**) | inner tab | 07-library-entities.png |
| Library / Calendar (month grid + markers) | inner tab | 08-library-calendar.png |
| Search (pushed; full note/article index) | nav → Search | 09-search.png |
| More menu (bottom sheet, 9 items) | nav → More | 10-more-menu.png |
| Settings sheet | More → Settings | 11-settings.png |
| Sync dashboard (Nextcloud passthrough, diagnostics) | Settings → Sync | 12-sync.png |
| Note editor (normal/preview, entity chip) | Library/Notes → note | 13-editor-normal.png |
| View-mode popup (Edit/Read/Preview/Source) | AppBar pencil | 14-viewmode-menu.png |
| Source editor + Magic FAB | popup → Source | 15-editor-source.png |
| Magic insert palette (Note link…Table, math, PDF) | Magic FAB | 16-magic-menu.png |
| Graph (1698-node hairball, 729 orphans) | More → Graph | 17-graph.png |
| Vaults sheet | More → Vaults | 18-vaults.png |
| Vault overflow (Disconnect / Delete permanently) | Vaults → ⋯ | 19-vault-actions.png |
| **Delete-vault confirm** (captured, then Cancelled) | ⋯ → Delete permanently | 20-delete-vault-confirm.png |
| Problems / **error surface** (dup day-file owners; raw Typst `[ERROR]…`) | More → Problems | 21-problems.png |

## Android (`screens/android/`)

| Screen | Reached via | File |
|---|---|---|
| First-run **"Allow vault folder access"** dialog (onboarding) | cold start (no vault) | 01-today-launch.png |
| Today (**empty vault**, "Nothing actionable today") | after grant | 02-today.png |
| Journal (single empty day card) | nav → Journal | 03-journal.png |
| Library / Notes (**empty**) | nav → Library | 04-library.png |
| Library / Articles (**empty**, import prompt, All·0) | inner tab | 05-library-articles.png |
| Search (1 result — empty vault) | nav → Search | 06-search.png |
| More menu (sheet) | nav → More | 07-more-menu.png |
| Settings sheet (Local folder = raw content:// URI) | More → Settings | 08-settings.png |
| Sync (**not connected**; raw URI shown) | Settings → Sync | 09-sync.png |

## NOT COVERED
- Reading mode (pushed screen), Split editor, Context/backlinks sub-pages, Typst-help, New-page create flow — not opened (breadth budget; no data-destructive value).
- Real note create/edit/delete **not executed**: note-level delete has no discoverable affordance in the shell, so a created scratch note would leak a file. Destructive-action coverage is via the delete-**vault** confirmation (captured + cancelled) instead.
- Android populated content: initially unavailable (empty Downloads folder). **Re-run addendum:** the vault was later re-synced to the real Nextcloud vault and re-crawled at full parity (5 notes / 1676 articles / 15 daily / 2 projects) — real-content captures `screens/android/r02-today.png`, `r03-journal.png`, `r05-library-articles.png`, `r06-search.png`. See report.md "Follow-up" section.
- Loading state: only transient cold-start; no isolated capture.
