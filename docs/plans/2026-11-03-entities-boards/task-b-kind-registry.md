# Task B: kind registry (custom icon + label per kind)

Depends on Task A. Read README.md P1.

- File `_system/settings/kinds.json` in the vault: `{"lab": {"icon": "science", "label": "Lab"}, ...}`. Synced like other `_system/settings/*.json` (see how calendars.json is read/written in lib/workspace_controller.dart ~730).
- Fixed icon palette: a const `Map<String, IconData>` of ~30 Material outline icons (person, place, business, work, science, school, groups, account_tree, hub, inventory, warehouse, build, event, language, folder, flag, star, bookmark, lightbulb, memory, palette, music_note, sports_esports, menu_book, apartment, computer, camera, local_library, biotech, category). Name keys are stable strings stored in JSON.
- `iconForKind` / `labelForKind` (lib/widgets/constants.dart) take the registry first, built-ins as fallback. Delete the duplicate switch in lib/knowledge_screen.dart (~635) and route through iconForKind. Registry is passed in or held in a simple app-level notifier; no new state-management dependency.
- New entity dialog (find where entityKindChoices from lib/entity_kinds.dart is used): when the chosen kind is new or has no registry entry, show an icon picker (grid of the palette) and save to kinds.json. Entity page header: tap the kind icon to change the kind's icon (affects all entities of that kind).
- Tests: registry overrides built-in; unknown icon name falls back; kinds.json round-trip; widget test that the New entity dialog writes the chosen icon.
- Done when flutter test for touched areas passes, dart analyze clean. Do not commit. Report files and tests.
