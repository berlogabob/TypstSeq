# TyLog

TyLog is a local-first, Typst-first journal and research workspace for Android and macOS. Android vaults live in a user-selected folder with persisted Storage Access Framework permission; optional Nextcloud WebDAV sync remains available. Notes, projects, articles, tasks, dates, citations, attachments, and reports remain ordinary `.typ` files. Whole Logseq and Obsidian vaults can be migrated in-app (Settings → Import): pages, journals, tasks, wikilinks, and assets convert into native TyLog notes. JSON is limited to settings, sync state, conflict records, diagnostics, and rebuildable indexes. An iOS host is included for iPad testing; iOS is not yet a release platform.

TyLog is also a small ecosystem: a versioned Typst package defines semantics,
`tylog_core` provides Flutter-independent indexing and validation, the
repository CLI supports headless vault work, and the Flutter app supplies the
interactive workspace. The shared metadata contract is
[TyLog Format v1](spec/tylog-format-v1.md); the complete boundary and
compatibility guide is [TyLog ecosystem](docs/tylog-ecosystem.md).

Mac index donor: `tool/launchd/org.tylog.indexer.plist` runs the existing CLI on `~/Nextcloud/TyLogVault`, watches daily/notes/articles/screenshots, and checks every 15 minutes (120-second throttle).

## Features

- Typed tasks: TODO / [] / /todo, status and priority commands, typed dates in English, Russian and Portuguese, repeats and editable chips.
- Doing runs the timer; Today, Tasks, Journal, Calendar, Search and saved queries share one task row.
- Image blocks with size, alignment and move controls; crop saves a new asset and keeps the original.
- Journal lists pages only, with events behind a collapsed Agenda line.
- Nextcloud upload confirmation and complete-listing checks; local sync safety copies in `.tylog/undo`, kept 30 days and excluded from sync.

Current release: 0.12.2+135. Recent behavior changes (0.12.1–0.12.2): Backspace on an empty task returns to plain text; typing during an upload no longer creates a conflict against this device's own earlier upload. Phone verification remains open.

## View modes and PDF export

- **Edit:** rich block editing.
- **Read:** reading view with adjustable typography and night mode.
- **Preview:** compiled Typst on one continuous screen-wide page, refitted on resize or rotation.
- **Source:** edit the note's Typst source.

PDF export uses Settings → **PDF page size**: A4 (default), Letter, A5, or
Legal. This applies to note sharing and report PDFs. Unmodified managed themes
upgrade automatically; a customized `_system/theme.typ` is not overwritten
and keeps its own layout unless adapted to the preview/export inputs.

## Development

Flutter stable with Dart 3.12 or newer is required. Native compiler setup is explicit and never runs as a build side effect:

```sh
./tool/setup_typst_native.sh
make test
flutter run -d macos
```

macOS builds require macOS 12 or newer. For an Apple Silicon release, run
`./tool/build_macos_arm64.sh` and open
`build/macos/Build/Products/Release/TyLog.app`. Set `FLUTTER_BIN` if Flutter is
not on your PATH. The standard `flutter build macos --release` also produces a
verified universal `x86_64` + `arm64` bundle under Xcode 27.

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
- [Changelog](CHANGELOG.md)
- [Implementation status](PLAN.md)
- [Application graph](graphify-out/GRAPH_REPORT.md)

Vault generation remains `5`. Existing v5 vaults open without note rewrites,
and their stable `/_system/tylog.typ` import continues to work. TyLog does not
automatically migrate pre-v5 vaults; back one up and initialize a clean v5
vault instead.
