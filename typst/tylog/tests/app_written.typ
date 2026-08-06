// Every task call shape the app can write, compiled against the SHIPPED
// package rather than a hand-written metadata literal. This is the check that
// was missing: a field the app emits but the package does not declare is a
// hard Typst error, and nothing caught it until 167 real notes stopped
// compiling.
#import "../lib.typ" as tylog

// Single-line, no trailing comma — what the in-app Task chip emits and what
// the writers' append branches must not corrupt.
#tylog.task(id: "single", text: "Single line", due: none, project: none)

// Multi-line with a trailing comma — what taskSnippet emits.
#tylog.task(
  id: "multi",
  text: "Multi line",
  status: "done",
  priority: "urgent",
)

// Time tracking, which lives in properties so an older package still reads it.
#tylog.task(
  id: "clocked",
  text: "Tracked",
  status: "done",
  properties: (
    "clocked": (("2025-12-25T12:33:43", "2025-12-27T09:15:31"), ("2025-12-28T10:02:11", none),),
  ),
)
