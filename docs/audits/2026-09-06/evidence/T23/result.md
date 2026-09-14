# T23 — bounded report dependency loading

Status: complete for the report export boundary.

`exportReportPdfStorage` now reads the report source once, compiles with an
empty per-export VFS, drains `TypstCompiler.takeRequestedFiles()` after each
attempt, validates each newly requested canonical path, and reads only those
bytes before retrying. It retains unique loaded paths, loaded bytes, and
compile attempts in the returned record. Missing, invalid, unreadable, and
non-progressing requests throw `ReportPreparationException`; PDF export and
atomic output writes remain outside the compile retry path.

Validation:

```text
flutter analyze lib/report.dart integration_test/share_pdf_native_test.dart  # clean
flutter test test/report_test.dart                                           # 4 passed
flutter test integration_test/share_pdf_native_test.dart -d macos            # 5 passed
flutter test integration_test/share_pdf_native_test.dart -d macos --plain-name 'report export loads only compiler-requested dependencies'  # 1 passed
```

The focused native run printed `loadedBytes=4200`, `11` unique
compiler-requested paths, `12` compile attempts, and `12` storage read calls
(the report source accounts for the extra read beyond the 11 dependencies).
The fixture computed the eligible whole-vault baseline as `7799` bytes,
including unrelated files; unrelated note, attachment, and old PDF each had
zero `readBytes` calls. The missing dynamic dependency fixture passed and also
verified zero unrelated reads. The scoped code/test diff is 244 additions and
33 removals; SHA-256:
`168b7bb2d5dce7fc046a59c39225a233b50d46d83ffbedc2babf811be2583bee`.

The export loop supports concrete dynamic requests produced by Typst and
stops visibly when a failed compile yields no new path. It intentionally does
not parse Typst source or diagnostic text, retain VFS state across exports, or
change the app/controller share flow.
