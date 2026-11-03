# Task F: project kanban (board file v1, columns layout)

Depends on Task A + D.

- Board file `boards/<id>.board.json` in the vault: `{"schema":1,"id":..,"title":..,"layout":"columns","scope":{"entity":"<entity id>"},"columns":{"field":"status","values":["todo","doing","done"],"showCancelled":false},"order":{"todo":["taskId",...],...}}`. Pure Dart model + read/write in tylog_core (json, no new deps). Index must ignore boards/ for notes but they must sync (check sync include rules).
- Scope: tasks whose `task.project` or containing note's partOf (transitively through childrenByParent descendants) matches the entity.
- UI: entity page gets a "Board" button (only when the entity has tasks in scope); opens a horizontal columns screen. Cards = TaskRow-like compact cards. Drag-and-drop with Flutter's DragTarget + LongPressDraggable (pattern from ~/Documents/GitHub/flutter-github-issues-todo/lib/screens/project_board_screen.dart:474-527; copy the idea, no dependency). Drop between columns calls applyTaskStatus (packages/tylog_core/lib/src/scanner/task_mutation.dart:46) through the same write path TaskRow.onSetStatus uses. Dropping into doing shows a snackbar if another clock was stopped. Reorder within a column updates `order` in the board file only.
- Board file is created lazily on first reorder; without it the view still works with default order.
- Tests: scope resolution (direct project, part_of descendant); drop writes status via applyTaskStatus and output compiles; board json round-trip; widget test drag todo->done.
- Done when tests pass, analyze clean. Do not commit. Report.
