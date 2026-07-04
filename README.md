# TyLog

TyLog is a local-first Typst journal and personal knowledge management app. Notes remain ordinary `.typ` files; search, backlinks, validation, and the graph are derived from the vault.

Current version: `1.0.0+23`

## Documentation

- [User handbook](USER_MANUAL.md) — installation, daily use, PKMS features, Nextcloud, backups, and troubleshooting
- [Project status](PLAN.md) — implemented scope, architecture, verification, and deferred work
- [Application graph](graphify-out/GRAPH_REPORT.md) — generated structural audit

## Development

Requirements: Flutter stable with Dart 3.12 or newer.

```sh
flutter pub get
flutter analyze
flutter test
flutter run -d macos
```

Useful release targets:

```sh
make help
make package-pages
make build-android
```

The web build is a landing page. The full application runs on Android, macOS, and Linux because its Typst preview and filesystem workflow require native support.

