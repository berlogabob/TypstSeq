# TyLog

TyLog is a local-first, Typst-first journal and research workspace for Android and macOS. Android vaults live in a user-selected folder with persisted Storage Access Framework permission; optional Nextcloud WebDAV sync remains available. Notes, projects, articles, tasks, dates, citations, attachments, and reports remain ordinary `.typ` files. JSON is limited to settings, sync state, conflict records, diagnostics, and rebuildable indexes. An iOS host is included for iPad testing; iOS is not yet a release platform.

TyLog is also a small ecosystem: a versioned Typst package defines semantics,
`tylog_core` provides Flutter-independent indexing and validation, the
repository CLI supports headless vault work, and the Flutter app supplies the
interactive workspace. The shared metadata contract is
[TyLog Format v1](spec/tylog-format-v1.md); the complete boundary and
compatibility guide is [TyLog ecosystem](docs/tylog-ecosystem.md).

## Development

Flutter stable with Dart 3.12 or newer is required. Native compiler setup is explicit and never runs as a build side effect:

```sh
./tool/setup_typst_native.sh
make test
flutter run -d macos
```

For an iPad development run, sign `ios/Runner.xcworkspace` with an Apple development team, then run `flutter run -d <device-id>`. The explicit native setup also prepares the checked local plugin for CocoaPods and Swift Package Manager; no build step downloads the compiler.

The complete release gates are:

```sh
make verify
```

Linux remains compile-tested in CI. Current implementation and manual verification work is tracked in [issue #42](https://github.com/berlogabob/TypstSeq/issues/42) with status `check needed`.

## Documentation

- [User handbook](USER_MANUAL.md)
- [TyLog ecosystem and CLI](docs/tylog-ecosystem.md)
- [TyLog Format v1](spec/tylog-format-v1.md)
- [Typst package](typst/tylog/README.md)
- [Implementation status](PLAN.md)
- [Application graph](graphify-out/GRAPH_REPORT.md)

Vault generation remains `5`. Existing v5 vaults open without note rewrites,
and their stable `/_system/tylog.typ` import continues to work. TyLog does not
automatically migrate pre-v5 vaults; back one up and initialize a clean v5
vault instead.
