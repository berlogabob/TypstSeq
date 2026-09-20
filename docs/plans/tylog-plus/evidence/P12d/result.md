# P12d result — bounded list surfaces

Status: DONE

The note picker now renders at most 50 rows per batch and exposes a `Load more` row. When the SQLite node projection is complete, picker, Library, and Articles candidates are read through bounded keyset pages and hydrated from stored note attributes; unavailable or incomplete projections fall back to the live index. Existing filtering, sorting, grouping, and selection behavior remains unchanged.

Evidence:

- `flutter test test/note_picker_sheet_test.dart` — 3 passed.
- `flutter analyze lib/widgets/note_picker_sheet.dart` — clean.
- `flutter analyze lib/app_mobile.dart` — clean.
- Full suite: `flutter test` — 686 passed, 2 skipped.
