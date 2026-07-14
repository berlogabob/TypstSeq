// TyLog Format v1 semantic and visual API.

#let identity(body) = body

#let default-tag-view(name) = text(fill: gray)[#name]

#let default-task-view(text-value, status, priority) = [
  #if status == "done" { "☑ " } else if status == "cancelled" { "☒ " } else { "☐ " }
  #text-value
]

#let document(
  body,
  paper: "a4",
  margin: 2cm,
  font: "Libertinus Serif",
  size: 11pt,
  heading-numbering: "1.1",
) = {
  set page(paper: paper, margin: margin)
  set text(font: font, size: size)
  set heading(numbering: heading-numbering)
  body
}

#let note(
  id: none,
  title: none,
  kind: "note",
  date: none,
  tags: (),
  aliases: (),
  project: none,
  properties: (:),
  transform: identity,
  body,
) = [
  #metadata((
    schema: 1,
    entity: "note",
    id: id,
    title: title,
    kind: kind,
    date: date,
    tags: tags,
    aliases: aliases,
    project: project,
    properties: properties,
  )) <tylog-note>
  #transform(body)
]

#let ref-note(target, body) = [
  #metadata((schema: 1, entity: "link", target: target, text: repr(body))) <tylog-link>
  #body
]

#let tag(name, view: default-tag-view) = [
  #metadata((schema: 1, entity: "tag", name: name)) <tylog-tag>
  #view(name)
]

#let date-ref(date, body) = [
  #metadata((schema: 1, entity: "date", date: date, text: repr(body))) <tylog-date>
  #body
]

#let attachment(path, kind: "file", body) = [
  #metadata((
    schema: 1,
    entity: "attachment",
    path: path,
    kind: kind,
    title: repr(body),
  )) <tylog-attachment>
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
  view: default-task-view,
) = [
  #metadata((
    schema: 1,
    entity: "task",
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
  #view(text, status, priority)
]

