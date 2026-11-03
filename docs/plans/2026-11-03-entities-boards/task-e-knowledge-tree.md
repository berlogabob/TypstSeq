# Task E: Knowledge/notes list as a tree

Depends on Task A + D.

- In the entity list (lib/widgets/work_surface.dart ~670-760 notes list, and lib/knowledge_screen.dart entity list): add a toggle "List | Tree". Tree: roots = entities with no resolvable parent; ExpansionTile-style rows expand to children (childrenByParent), multi-parent node appears under every parent, cycles guarded (stop when an id repeats on the path). Remember toggle per screen like existing persisted choices (work_surface.dart ~818).
- Search/filter in tree mode shows matching nodes with their ancestor path.
- Tests: tree builder pure function (roots, multi-parent, cycle) + one widget test.
- Done when tests pass, analyze clean. Do not commit. Report.
