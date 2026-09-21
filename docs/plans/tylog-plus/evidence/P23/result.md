# P23 — complete research workflow

Status: RUNNING

The existing workflow selects notes by project, kind, tags, date, and article status, then emits deterministic Typst report source. Notes with citations append the vault bibliography, and Zotero-enabled reports include both bibliography sources. The same vault files and report writer are used on desktop and mobile storage adapters.

Evidence:

- `flutter test test/report_test.dart` — filtering, deterministic report source, citation bibliography, and Zotero output pass.
- `flutter test test/report_test.dart test/portable_roundtrip_test.dart` — report and portable workflow checks pass.
- `flutter test test/report_test.dart` — an integration case now filters the shared index and writes the resulting deterministic Typst report through the real `VaultStorage` adapter.

## Search navigation (2026-09-21)

The `KnowledgeScreen` widget suite now covers a populated retrieval result and
verifies tapping it hands the durable vault-relative note path to the existing
open-note callback. The host search-to-note handoff passes; vector-backed result
ranking, citation offsets, and native workflow acceptance remain open.

P24 remains the production rehearsal gate for process interruption, disk pressure, permissions, migration, and real-device timing.

Acceptance correction (2026-09-20): the host write path is now covered, but this does not close the full milestone. Retrieval-to-report UI wiring, cited navigation, and native end-to-end checks remain; see the execution ledger.

`notesForSearchResults` now bridges ranked retrieval rows to current vault notes
in caller order, de-duplicates stable IDs, and skips stale rows. This provides
a safe host seam for feeding retrieved notes into the existing report writer;
vector ranking, citation offsets, and native workflow checks remain open.
