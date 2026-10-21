# Settings as Pages Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Settings opens a short home page of six groups; each group (and each AI part) is its own page with Back navigation; device-only settings carry a scope label.

**Architecture:** `SettingsSheet` keeps its constructor (it already carries every value/callback) and becomes the home page; group pages receive that widget as `settings` and read from it (deviation from the spec's separate `SettingsActions` class: the widget is that object). Existing widgets move into pages unchanged, except `AudioProcessingSettings`, which gains a `section` parameter.

**Tech Stack:** Flutter (Material 3), existing design tokens in `lib/widgets/constants.dart`, `AppSection`/`AppTile` in `lib/widgets/ds/`.

**Spec:** `docs/superpowers/specs/2026-10-21-settings-pages-design.md`

## Global Constraints
- Groups and order: General, Calendars, AI, Sync and storage, Maintenance, About.
- AI subpages: Servers, Audio, Articles, Screenshots.
- Scope labels: "This device" (Appearance, PDF page size, Task reminders, Local folder); "This Mac" (Screenshot folder).
- "Right after it is added" = mode `both`; "On schedule" = `schedule`; "Only when I ask" = `off`.
- Spacing via `kSpace*`, colours via the theme, no raw `Colors.*` (design_tokens_test).
- System Back must leave each page; More → Settings and the Mac menu open the home page.
- Delegation: codex `gpt-5.6-luna` for multi-file edits; Ornith (Studio, Unsloth) only for new self-contained files; Claude reviews every diff.

## Review Focus
1. A setting that disappears in the move: walk test (Task 4) lists every setting title and finds each one.
2. Back on Android from a subpage returns to the previous page, not out of Settings: walk test presses `tester.pageBack()` per level.
3. Values changed on a subpage show on the home summary when returning: home rebuilds on pop (Task 3 test).
4. Narrow phone (360 dp) and large font: home rows don't overflow (Task 3 test at 360 dp, textScaler 1.3).
5. Screenshot mode `both` shows "Right after it is added" (Task 1 test).

---

### Task 1: Screenshot catch-up rule
**Files:** Modify `lib/widgets/screenshots_settings.dart` (onChanged mapping, fly/sched flags); Test `test/screenshots_test.dart`.
- [ ] Failing test: `ScreenshotsSettings(mode: 'both', …)` shows "Right after it is added" selected; tapping it again keeps `both`; tapping "Right after it is added" from `off` calls `onConfigure('both', time)`.
- [ ] Implement: `final fly = mode == 'watch' || mode == 'both'; final sched = mode == 'schedule';` and `next = nextFly ? 'both' : nextSched ? 'schedule' : 'off'`.
- [ ] Update the existing test that expected `watch:03:00` to `both:03:00`. Run `flutter test test/screenshots_test.dart` → PASS. Commit.

### Task 2: AudioProcessingSettings sections
**Files:** Modify `lib/widgets/audio_processing_settings.dart`; Test `test/audio_widgets_test.dart`.
**Produces:** `enum AiSettingsSection { all, servers, audio, articles, screenshots }` and `AudioProcessingSettings(section: …)` (default `all` = today's output).
- [ ] Failing test: `section: AiSettingsSection.servers` shows `AiConnectionsSection` and not 'Transcription quality'; `audio` shows 'Transcription quality', 'Transcribe automatically' and languages, not 'Articles'; `articles` shows only the Articles server/model; `screenshots` only the Screenshots server/model.
- [ ] Implement by wrapping each existing block in `if (show(section))` — no logic changes. Run `flutter test test/audio_widgets_test.dart test/ai_connections_settings_test.dart` → PASS. Commit.

### Task 3: Pages and home
**Files:**
- Create (Ornith, new files only): `lib/widgets/settings/scope_note.dart` (`class ScopeNote extends StatelessWidget { const ScopeNote(this.text); }` renders `bodySmall` in `onSurfaceVariant`), `lib/widgets/settings/settings_page.dart` (`class SettingsPage extends StatelessWidget { const SettingsPage({required this.title, required this.children}); }` = `Scaffold(appBar: AppBar(title: Text(title)), body: ListView(padding: EdgeInsets.symmetric(vertical: kSpace8), children: children))`).
- Create (codex): `lib/widgets/settings/general_page.dart`, `ai_page.dart` (four rows → `SettingsPage` with `AudioProcessingSettings(section: …)` / `ScreenshotsSettings`), `sync_storage_page.dart`, `maintenance_page.dart`, `about_page.dart`, `calendars_page.dart` (today's calendar sheet body as a page). Each takes `final SettingsSheet settings;`.
- Modify (codex): `lib/widgets/settings_sheet.dart` build → `Scaffold(appBar: AppBar(title: Text('Settings')), body: ListView` of six `ListTile`s (title, one-line summary subtitle, chevron) that `Navigator.push(MaterialPageRoute(builder: (_) => XPage(settings: widget)))`, then `setState` on return.
- Modify: `lib/app_mobile.dart` `_showSettings`: `Navigator.of(context).push(MaterialPageRoute(builder: (_) => SettingsSheet(...)))` instead of `showModalBottomSheet`.
- Test: `test/settings_sections_test.dart` (update), `test/preview_theme_test.dart` (update).
- [ ] Failing test: home shows exactly the six group titles; at 360 dp with textScaler 1.3 no overflow; after popping General with a changed PDF size the home summary shows it.
- [ ] Implement; scope labels via `ScopeNote('This device')` / `ScopeNote('This Mac')` per Global Constraints.
- [ ] Run `flutter test test/settings_sections_test.dart test/preview_theme_test.dart test/design_tokens_test.dart test/mobile_navigation_creation_test.dart` → PASS. Commit.

### Task 4: Walk test, docs, devices
**Files:** Create `test/settings_walk_test.dart`; Modify `USER_MANUAL.md` (menu paths).
- [ ] Walk test: open home; for each group and AI subpage push, assert its settings (Appearance, PDF page size, Task reminders; Calendars list; Servers, Transcription quality, Articles, Screenshots (OCR); Local folder, Vaults, Sync; Problems … Semantic search; App version, Check for updates, Typst help) are found, then `tester.pageBack()` returns to the previous page.
- [ ] Update manual paths ("Settings > AI > Servers", "Settings > General", "Settings > Calendars", "Settings > Sync and storage > Sync").
- [ ] Full `flutter test` + `flutter analyze`; commit; build APK, install on P30 and A24, check navigation and Back; build Mac, install, check.
