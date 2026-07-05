# TyLog

TyLog is a local-first, Typst-first journal and research workspace for Android and macOS. Notes, projects, articles, tasks, dates, citations, attachments, and reports remain ordinary `.typ` files. JSON is limited to settings, sync state, and rebuildable indexes. An iOS host is included for iPad testing; iOS is not yet a release platform.

## Development

Flutter stable with Dart 3.12 or newer is required. Native compiler setup is explicit and never runs as a build side effect:

```sh
./tool/setup_typst_native.sh
flutter analyze
flutter test
flutter run -d macos
```

For an iPad development run, sign `ios/Runner.xcworkspace` with an Apple development team, then run `flutter run -d <device-id>`. The explicit native setup also prepares the checked local plugin for CocoaPods and Swift Package Manager; no build step downloads the compiler.

The complete release gates are:

```sh
make verify
```

The web target is a landing page. Linux remains compile-tested in CI. Current implementation and manual verification work is tracked in [issue #42](https://github.com/berlogabob/TypstSeq/issues/42) with status `check needed`.

## Documentation

- [User handbook](USER_MANUAL.md)
- [Implementation status](PLAN.md)
- [Application graph](graphify-out/GRAPH_REPORT.md)

TyLog v5 intentionally does not migrate older vaults. Back up the old vault, create a clean v5 vault, and use a new empty Nextcloud remote folder.
