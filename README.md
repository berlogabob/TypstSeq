# TyLog

TyLog is a local-first, Typst-first journal and research workspace for Android and macOS. Notes, projects, articles, tasks, dates, citations, attachments, and reports remain ordinary `.typ` files. JSON is limited to settings, sync state, and rebuildable indexes.

## Development

Flutter stable with Dart 3.12 or newer is required. Native compiler setup is explicit and never runs as a build side effect:

```sh
./tool/setup_typst_native.sh
flutter analyze
flutter test
flutter run -d macos
```

The complete release gates are:

```sh
make verify
```

The web target is a landing page. Linux remains compile-tested.

## Documentation

- [User handbook](USER_MANUAL.md)
- [Implementation status](PLAN.md)
- [Application graph](graphify-out/GRAPH_REPORT.md)

TyLog v5 intentionally does not migrate older vaults. Back up the old vault, create a clean v5 vault, and use a new empty Nextcloud remote folder.
