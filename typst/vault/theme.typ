// tylog-theme-version: 2
#let document(body) = {
  if "tylog-page-width" in sys.inputs {
    set page(width: float(sys.inputs.at("tylog-page-width")) * 1pt, height: auto, margin: 12pt)
    set text(font: "Libertinus Serif", size: 11pt)
    set heading(numbering: "1.1")
    body
  } else {
    set page(paper: sys.inputs.at("tylog-paper", default: "a4"), margin: 2cm)
    set text(font: "Libertinus Serif", size: 11pt)
    set heading(numbering: "1.1")
    body
  }
}

