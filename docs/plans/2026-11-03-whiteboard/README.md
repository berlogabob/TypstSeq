# P3: whiteboard (Logseq-like canvas)

Parent: docs/plans/2026-11-03-entities-boards/README.md primitive 2 (Board). One board file, several layouts: `columns` (kanban, P1), `free` (whiteboard), `tree` (auto layout over part_of).

## Board file v2 (`boards/<id>.board.json`, schema 2, readers accept 1)
```json
{"schema":2,"id":"b1","title":"IADE map","layout":"free",
 "cards":[{"id":"c1","type":"note|entity|task|asset|url|text","ref":"<note id | task id | asset path | url>","text":"<for text cards>","x":0,"y":0,"w":240,"h":120,"color":null,"frame":null}],
 "frames":[{"id":"f1","title":"Labs","x":-40,"y":-40,"w":800,"h":600}],
 "edges":[{"id":"e1","from":"c1","to":"c2","label":""}],
 "viewport":{"x":0,"y":0,"zoom":1}}
```
Rules: cards reference vault content by id (never copy note text); images pasted/dropped are copied to `assets/boards/<board id>/<sha8>.<ext>`; unknown keys preserved; a missing ref renders as a "missing" card, never crashes.

## UI
- Library > Boards tab (list + New whiteboard); entity page "Whiteboard" action creates/opens a board scoped to the entity.
- Canvas: InteractiveViewer pan/zoom (reuse graph.dart pattern), cards as positioned widgets (note: title + excerpt + kind icon; task: TaskRow compact; asset: image thumbnail; url: title/host; text: editable text), drag to move (snap 8 px), resize handle, select + delete, connect mode (drag from a card handle to another card), frames (drag to move contents).
- Add: "+" menu (Note/entity/task via existing choosers, Text, Link, Image from file), paste (image or URL from clipboard), desktop drag-drop of files/URLs only if an existing dependency supports it (no new dependency in P3).
- Open a card: tap opens the note/task/url.
- Tree layout: from an entity, children via childrenByParent laid out top-down (tidy tree), read-only; "Pin to whiteboard" converts to free cards + edges.
- Performance: only visible cards build (viewport culling); boards up to 500 cards smooth on P30.
