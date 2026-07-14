#metadata((
  schema: 1,
  entity: "note",
  id: "fixture-note",
  title: "Format fixture",
  kind: "research",
  date: "2026-07-14",
  tags: ("format", "fixture"),
  aliases: ("contract",),
  project: "tylog",
  properties: (source: "fixture", rating: 5),
)) <tylog-note>

#metadata((schema: 1, entity: "link", target: "other-note", text: "Other")) <tylog-link>
#metadata((schema: 1, entity: "tag", name: "contract")) <tylog-tag>
#metadata((schema: 1, entity: "date", date: "2026-07-20", text: "Review")) <tylog-date>
#metadata((schema: 1, entity: "attachment", path: "assets/spec.pdf", kind: "file", title: "Spec")) <tylog-attachment>
#metadata((
  schema: 1,
  entity: "task",
  id: "fixture-task",
  text: "Verify the contract",
  status: "doing",
  priority: "high",
  project: "tylog",
  scheduled: "2026-07-14",
  due: "2026-07-20",
  dependencies: (),
  assignees: ("BerlogaBob",),
  tags: ("contract",),
  completed: (),
  properties: (source: "fixture"),
)) <tylog-task>

= Format fixture

Backlinks are derived by resolving the `other-note` link against the complete
vault index; they are not duplicated in note metadata.

