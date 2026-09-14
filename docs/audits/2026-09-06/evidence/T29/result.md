# T29 — native compiler request seam

Status: complete for the native Rust and generated bridge scope.

Implemented `SimpleWorld` request recording at the existing `source` and
`file` resolver boundary. Requests use the same canonical `vfs_key` as
lookups, are deduplicated and sorted in a `BTreeSet`, and are returned by the
draining `TypstEngine.take_requested_files` bridge API. The Dart bridge and
`TypstCompiler.takeRequestedFiles()` wrapper were regenerated/updated.

Validation:

```text
cargo test requested_files --lib  # 1 passed
cargo test --lib                  # 19 passed, 0 failed
cargo check                       # passed
/Users/berloga/.cargo/bin/flutter_rust_bridge_codegen generate  # Done!
dart format --output=none packages/typst_flutter/lib/src/compiler.dart packages/typst_flutter/lib/src/rust/api/typst.dart packages/typst_flutter/lib/src/rust/frb_generated.dart packages/typst_flutter/lib/src/rust/frb_generated.io.dart  # 0 changed
git diff --check -- <scoped native/bridge files>  # passed
```

The scoped native/bridge diff is 279 added and 15 removed lines across the
five scoped source/generated files. Content hash:
`ca7e4aca8c4db3f3944546108868feedd40306bb87dd7e550c7fcc89e9d4187e`.

Limitations: recording is per engine and only observes requests made through
Typst's normal `source`/`file` calls; it does not read storage or implement
retry policy. A dynamic dependency is reported when Typst evaluates it to a
concrete request; a dependency that never produces a concrete resolver call
remains the caller's preparation failure. The main source file is excluded
from the request set because the caller already owns its bytes.
