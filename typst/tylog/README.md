# TyLog for Typst

TyLog `0.1.0` emits the stable metadata labels used by the TyLog Flutter app
and repository CLI. It is deliberately small: `note`, `ref-note`, `tag`,
`date-ref`, `attachment`, and `task` provide semantics; `document` and the
configurable task/tag views provide presentation.

```typst
#import "@preview/tylog:0.1.0" as tylog
#show: tylog.note.with(id: "hello", title: "Hello")

= Hello

#tylog.task(id: "first", text: "Try TyLog")
```

The package is vendored by TyLog vaults for offline compilation. Registry
publication is not part of version `0.1.0`; the preview import above documents
the intended future registry address.

See `spec/tylog-format-v1.md` in the TypstSeq repository for the metadata
contract and compatibility rules.

