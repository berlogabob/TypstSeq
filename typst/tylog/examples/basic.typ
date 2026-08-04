#import "../lib.typ" as tylog

#show: tylog.note.with(
  id: "example",
  title: "TyLog package example",
  kind: "note",
  tags: ("typst", "tylog"),
  transform: tylog.document,
)

= TyLog package example

#tylog.tag("example") links to #tylog.ref-note("other")[another note],
was written on #tylog.date-ref("2026-08-03")[today], and cites
#tylog.attachment("assets/spec.pdf", kind: "file")[the spec].

#tylog.task(
  id: "example-task",
  text: "Compile the package example",
  status: "done",
  priority: "normal",
)

