# Scanner split result

Split `packages/tylog_core/lib/src/scanner.dart` into exactly three parts, in the requested order. Ranges below refer to the original 2,949-line file and include trailing separator blank lines.

| New file | Original line ranges moved | Contents |
| --- | --- | --- |
| `packages/tylog_core/lib/src/scanner/task_mutation.dart` | 1656–2163 | `const _keep` through `_identifierStart`, including task mutations, field contracts, and structural field helpers. |
| `packages/tylog_core/lib/src/scanner/header_repair.dart` | 1248–1655 | `replaceNoteHeader` through `_parsePropertyValue`, including import/article repair, Logseq cleanup, entity migration, and property parsing/editing. |
| `packages/tylog_core/lib/src/scanner/link_resolution.dart` | 52–100; 1188–1247; 2809–2829 | Resolver enum/classes, public resolution/suggestion helpers, `_add`, and `_resolveCandidates`. |

Each part starts with `part of '../scanner.dart';`. The parent lists the three part directives after all imports; its imports are unchanged. Public declarations and class methods retain their signatures and library visibility. Shared parsing and serialization primitives remain in the parent. The parent is now 1,907 lines.

Read AGENTS.md, CONTEXT.md Engineering rules, and the project-memory `tylog-megafile-split-recipe.md`. After each group, read its references and their definitions/imports:

- Task mutation: `ClockEntry` is supplied by `models.dart`, `typstString` by `values.dart`; call/dictionary/clock parsing and character-scanning helpers remain in the same library.
- Header repair: `NoteMetadataDraft`, `_noteHeader`, field/list readers, serialization helpers, and character-scanning helpers remain in the parent; structural field and append helpers are available through the task part. `typstString` remains imported from `values.dart`.
- Link resolution: `NoteRef` and `VaultIndex` are supplied by `models.dart`; `_typExtension` remains shared in the parent; candidate helpers moved with the resolver.

No missing import was identified by these reading checks. A byte comparison against the pre-edit source confirmed every moved block is verbatim, and the parent differs only by those removals and the part directives. No `lib/import/legacy_import_*.dart` file was changed. No commit was made.

## Uncertainty and deferred validation

Flutter, Dart, formatting, analysis, and tests were not run, as requested. The coordinator must establish analyzer/test results; the checks here establish source preservation and library wiring only.

Ran the required `graphify update .` (AST-only, no LLM). It refreshed graph artifacts and reported partial extraction for unrelated `linux/runner/my_application.h` and `packages/typst_flutter/android/build.gradle`, plus files yielding no symbols. Community membership changed, and Graphify renamed 87 communities by their hubs; semantic relabeling was not run. These warnings limit confidence in the generated graph, not in the byte-preserving split.
