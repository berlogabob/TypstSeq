# P12 editor candidates — diagnostic only

These isolated experiments are not ready for production. Super Editor failed
the Mac diagnostic; Quill produced conflicting fail/pass results. They are not
part of TyLog and do not add dependencies to its application package.

```bash
tool/editor_candidates/run.sh super_editor macos --no-dds
tool/editor_candidates/run.sh super_editor macos --no-dds --dart-define=P12_SINGLE_PARAGRAPH=true
tool/editor_candidates/run.sh flutter_quill macos --no-dds
```

The runner creates a disposable Flutter project, prints its location, and retains
the driver JSON there (including failed runs). It pins Super Editor
`0.3.0-dev.52` or Flutter Quill `11.5.1`; transitive dependencies are resolved by
pub and recorded in the generated lockfile. Sources have `.template` extensions
because they belong to that isolated package, not TyLog's analyzer context.
The generated application ID is `org.tylog.probe.tylogEditorProbe` on macOS and
`org.tylog.probe.tylog_editor_probe` on Android; neither accesses the production
vault. Android runs are optional and unmeasured.

The default diagnostic uses 900 rows with a bold first phrase, appends a
character every 250 ms for 20 seconds, checks exact plain text, and applies the
shared build/raster metric at the observed refresh rate. Acceptance requires
at least three edits and frame samples per second and strictly less than 1%
over-budget frames. A successful short run alone does not establish acceptance.

This is model-driven input, not keyboard/IME or TyLog source-format acceptance.
The single-paragraph Super Editor fixture preserves hard newlines inside one
node. Quill uses newlines as paragraph delimiters, so its optional single-node
fixture joins rows with spaces instead; that variant has not been measured.

See [P12 evidence](../../docs/plans/tylog-plus/evidence/P12e/result.md) for
results, remaining correctness checks, and the full five-minute device gate.
