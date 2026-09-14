# T22 — bounded report dependency contract

## Current boundary

`writeReportStorage` generates a report that imports `/_system/export.typ`,
includes the selected note paths, and conditionally references
`/_system/bibliography.yml` and `/_system/zotero.bib`. The exporter currently
lists the whole vault and reads every non-cache file before calling the Typst
compiler. That includes unrelated notes, attachments, old output PDFs, and
the generated report itself.

The embedded compiler's `SimpleWorld` is the authority for resolution. Its
`source` and `file` methods receive Typst's resolved `FileId`; `vfs_key` maps
project files to their normalized vault-relative paths and package files to
`_system/packages/{name}/{version}/{path}`. It already handles relative,
rooted, and `@namespace/name:version` package imports. The Dart bridge only
accepts a prebuilt byte map and does not currently expose requested paths.

## T23 contract

1. Do not parse report/note Typst with a Dart regex, and do not infer a
   closure from compiler diagnostic text. Extend the existing `SimpleWorld`
   resolver to record its canonical VFS key on every non-main `source` and
   `file` request. Expose a `takeRequestedFiles()`-style bridge operation
   which returns and clears that set after each compile attempt. It must use
   the same `vfs_key` used for lookup, including the package-root mapping.
2. `exportReportPdfStorage` reads the report source once, then compiles with
   an initially empty per-export VFS. After a failed attempt, read only newly
   recorded canonical paths from `VaultStorage`, add those bytes under the
   same single unprefixed key, and retry. On success, write the PDF as today.
   The preparation result records unique paths, loaded bytes, and attempts.
   Do not retain this VFS across exports.
3. A requested path that is missing, unreadable, invalid for vault storage,
   or produces no newly requested paths on a failed attempt is a preparation
   failure. Surface it before sharing; never fall back to reading the vault.
   A dynamically constructed import is supported when the compiler evaluates
   it to a concrete VFS request. A dynamic dependency that cannot converge
   under this process fails visibly with its compiler/preparation diagnostic.
4. Preserve existing output naming, atomic `writeBytes`, returned PDF bytes,
   compiler/document disposal, and the normal share flow. While resolving,
   `app_mobile.dart` shows `Preparing report…`; show the caught failure rather
   than the success snack/share sheet.

The native request-recording seam is required for T23. If its bridge change
cannot be made as a bounded update, stop and split it into a compiler task;
the safe fallback is a visible unresolved-dependency failure, never a regex
or whole-vault read.

## Fixture and acceptance checks

Add a `test/report_test.dart` fixture using a counting `VaultStorage`, clearing
counts after vault setup. Generate a report for `notes/root.typ`; it imports
`../shared/static.typ`, includes a dynamically constructed `../shared/dynamic.typ`,
uses `#image("../assets/needed.png")`, reads a data file, imports
`@preview/tylog:0.1.0`, and has citations so generated source loads the YAML
bibliography (repeat with Zotero). Include the normal export/theme/helper and
vendored package files. Put `notes/unselected.typ`, a large
`assets/unrelated.bin`, and an old `outputs/unrelated.pdf` beside them.

Assert PDF signature and required content/import resolution against the
current full-map baseline. Assert every required path was read, each unrelated
path has zero `readBytes` calls, and recorded loaded bytes equal the counter's
sum of unique required reads. Compare page count only in a deterministic
fixture using the same bundled compiler/fonts. Add a separate dynamic-missing
case that asserts preparation fails visibly and still performs zero unrelated
reads.

## Minimal expected files

`packages/typst_flutter/rust/src/api/typst.rs` plus regenerated bridge bindings
and `packages/typst_flutter/lib/src/compiler.dart` for resolver requests;
`lib/report.dart`, the report action in `lib/app_mobile.dart`, and
`test/report_test.dart`. Keep `packages/tylog_core/lib/src/report.dart`
unchanged unless T23 needs to carry selected-note metadata to reduce attempts.

## Evidence

- `lib/report.dart:55-70` performs the whole-vault byte read.
- `packages/typst_flutter/rust/src/api/typst.rs:438-493` canonicalizes and
  resolves all compiler VFS file requests.
- `packages/tylog_core/lib/src/report.dart:55-64` defines generated report
  imports, notes, and bibliography references.
