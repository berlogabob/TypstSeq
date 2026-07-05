// tylog-helper-version: 5
#import "theme.typ" as theme

#let note(
  id: none,
  title: none,
  kind: "note",
  date: none,
  tags: (),
  aliases: (),
  project: none,
  properties: (:),
  body,
) = [
  #metadata((
    id: id,
    title: title,
    kind: kind,
    date: date,
    tags: tags,
    aliases: aliases,
    project: project,
    properties: properties,
  )) <tylog-note>
  #theme.document(body)
]

#let ref-note(target, body) = [
  #metadata((target: target, text: repr(body))) <tylog-link>
  #body
]

#let tag(name) = [
  #metadata(name) <tylog-tag>
  #text(fill: gray)[#name]
]

#let date-ref(date, body) = [
  #metadata((date: date, text: repr(body))) <tylog-date>
  #body
]

#let attachment(path, kind: "file", body) = [
  #metadata((path: path, kind: kind, title: repr(body))) <tylog-attachment>
  #body
]

#let task(
  id: none,
  text: none,
  status: "todo",
  priority: "normal",
  project: none,
  scheduled: none,
  due: none,
  remind: none,
  timezone: none,
  recurrence: none,
  dependencies: (),
  assignees: (),
  tags: (),
  completed: (),
  properties: (:),
) = [
  #metadata((
    id: id,
    text: text,
    status: status,
    priority: priority,
    project: project,
    scheduled: scheduled,
    due: due,
    remind: remind,
    timezone: timezone,
    recurrence: recurrence,
    dependencies: dependencies,
    assignees: assignees,
    tags: tags,
    completed: completed,
    properties: properties,
  )) <tylog-task>
  #if status == "done" { "☑ " } else { "☐ " }
  #text
]
