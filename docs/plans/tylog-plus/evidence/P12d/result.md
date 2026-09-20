# P12d progress — bounded list surfaces

Status: RUNNING

The note picker now renders at most 50 rows per batch and exposes a `Load more` row. When the SQLite node projection is complete, picker candidates are read through bounded keyset pages and hydrated from stored note attributes; unavailable or incomplete projections fall back to the live index. Filtering and selection remain unchanged. Library and Articles still consume `VaultIndex` directly and require the same hydration seam before switching to `pageNodeSummaries`.

Evidence:

- `flutter test test/note_picker_sheet_test.dart` — 3 passed.
- Full suite: `flutter test` — 685 passed, 2 skipped.
- `flutter analyze lib/widgets/note_picker_sheet.dart` — clean.
- `flutter analyze lib/app_mobile.dart` — clean.
