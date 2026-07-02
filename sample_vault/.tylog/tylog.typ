#let note(title: none, date: none, tags: (), aliases: ()) = none

#let wikilink(target, display: none) = {
  if display == none { target } else { display }
}

#let tag(name) = [#name]
