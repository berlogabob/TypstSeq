// tylog-export-version: 1
#import "theme.typ" as theme
#let report(title, body) = theme.document([
  #heading(level: 1, title)
  #body
])
