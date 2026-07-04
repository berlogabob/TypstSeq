#import "/.tylog/tylog.typ" as pkm

#pkm.note(
  id: "root-note",
  title: "Root note",
  tags: ("pkms",),
  aliases: ("root",),
  links: ("child-note",),
  files: ("manual-doc",),
)

= Root note

Link: #pkm.link("child-note")
