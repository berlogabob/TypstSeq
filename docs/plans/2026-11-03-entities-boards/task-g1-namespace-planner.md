# Task G1 (pi): pure namespace planner

Create exactly two NEW files. Do not edit any other file.

1. `packages/tylog_core/lib/src/namespace_plan.dart`
```dart
class NamespacePage { final String id; final String title; final List<String> aliases; const NamespacePage(this.id, this.title, this.aliases); }
class NamespaceChange {
  final String? existingId;   // page being changed, or null when the page must be created
  final String fullPath;      // "A/B/C"
  final String newTitle;      // "C"
  final String? parentPath;   // "A/B", null for a root segment
  const NamespaceChange({this.existingId, required this.fullPath, required this.newTitle, this.parentPath});
}
class NamespacePlan { final List<NamespaceChange> changes; final List<String> skipped; const NamespacePlan(this.changes, this.skipped); }
NamespacePlan planNamespaces(List<NamespacePage> pages);
```
Rules:
- A page is namespaced when its title contains `/`. Split on `/`, trim segments.
- Skip (add title to `skipped`) when: any segment is empty after trim, title contains `://`, title starts with `r/` or `u/`, or the title matches `^\d{4}/\d{4}` (academic years like "2026/2027"), or any segment is longer than 80 chars.
- For each namespaced page `A/B/C`: one change for it (existingId = its id, newTitle "C", parentPath "A/B"); then ensure each ancestor path ("A/B", "A") has exactly one change across the whole plan: if a page exists whose title or alias equals the ancestor path, or whose title equals the last segment AND that page already has the ancestor path in aliases, use its id as existingId; otherwise existingId null (to be created). Ancestor change for "A/B" has newTitle "B", parentPath "A"; for "A" newTitle "A", parentPath null.
- Matching is case-insensitive. No duplicate changes for the same fullPath (case-insensitive). Order: sorted by fullPath depth then alphabetically.
- Idempotent: a page already titled "C" with alias "A/B/C" is not namespaced (no `/` in title) and must not produce a change.
- No imports beyond dart:core.

2. `packages/tylog_core/test/namespace_plan_test.dart` (package:test) covering: basic 3-level creates 2 ancestors; existing ancestor by title "A/B" reused; existing ancestor by alias reused; URL / "2026/2027" / "r/foo" / empty segment skipped; shared ancestor across two pages yields one change; case-insensitive dedupe; Cyrillic titles ("poplar bear/Проект/Мебель").

Verify: `cd packages/tylog_core && dart test test/namespace_plan_test.dart` passes and `dart analyze lib/src/namespace_plan.dart test/namespace_plan_test.dart` is clean.
