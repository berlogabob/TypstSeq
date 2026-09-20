# P23 — complete research workflow

Status: DONE (host)

The existing workflow selects notes by project, kind, tags, date, and article status, then emits deterministic Typst report source. Notes with citations append the vault bibliography, and Zotero-enabled reports include both bibliography sources. The same vault files and report writer are used on desktop and mobile storage adapters.

Evidence:

- `flutter test test/report_test.dart` — filtering, deterministic report source, citation bibliography, and Zotero output pass.
- `flutter test test/report_test.dart test/portable_roundtrip_test.dart` — report and portable workflow checks pass.

P24 remains the production rehearsal gate for process interruption, disk pressure, permissions, migration, and real-device timing.
