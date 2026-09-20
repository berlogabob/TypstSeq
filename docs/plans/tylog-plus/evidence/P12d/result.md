# P12d progress — bounded list surfaces

Status: RUNNING

The note picker now renders at most 50 rows per batch and exposes a `Load more` row. Filtering and selection remain unchanged; this removes the initial widget-build cost for large picker inputs. Library and Articles still consume `VaultIndex` directly and require an async database-page hydration seam before switching to `pageNodeSummaries`.

Evidence:

- `flutter test test/note_picker_sheet_test.dart` — 3 passed.
- `flutter analyze lib/widgets/note_picker_sheet.dart` — clean.
