# TyLog Module Pack (`.tylogpack`) v1

A data-only zip. Nothing in a pack executes. Implementation:
`packages/tylog_core/lib/src/module_pack.dart`; app flow: Settings -> Install module
(`lib/app_mobile/module_flow.dart`). Reference pack: BerloPortuga `tools/pack.py`.

## Layout
```
manifest.json
notes/**.typ     TyLog format v1 notes (spec/tylog-format-v1.md)
assets/**        audio, images (anything)
```
`manifest.json`: `{"schema":1, "id":"pt-pt-a2b1", "name":..., "version":"1.0.0",
"files":[{"path":"notes/0001.typ","sha256":"<hex>"}, ...]}`.
`id` matches `[a-z0-9][a-z0-9-]{0,63}`. Every file except the manifest must be
listed and hash-verified; unlisted or traversal paths reject the pack.
Optional strings: `unit` labels progress (e.g. `"lessons"`; default `"tasks"`),
`lang` identifies the content language, and `description` describes the pack.
The install record retains `unit`; old records default to `"tasks"`.

## Install mapping (inside synced vault prefixes only)
- `notes/x` -> `projects/<id>/x`
- `assets/x` -> `assets/modules/<id>/x`
- record -> `_system/modules/<id>.json` (installed hashes)

## Tokens in notes (resolved at install)
- `{{id}}` pack id (use in attachment paths: `assets/modules/{{id}}/audio/a.mp3`)
- `{{due:N}}` user start date + N days, ISO. Put it in `#tylog.task(due: ...)`
  so the lesson shows in the agenda and calendar. Packs carry offsets, never dates.

## Rules for authors
- Notes must be self-contained: the in-app Typst compile has only
  `_system/tylog.typ`, so no custom `#import` or layout macros.
- Audio: `#tylog.attachment("<path>", kind: "audio")[label]`.
- Optional waveform sidecars sit beside audio: `assets/audio/a.mp3.peaks`.
  Include them in `files` with their own hash. Content is ASCII hex, two
  characters per bucket, 200 buckets (400 characters). The app reads them
  before decoding audio, falls back if missing/invalid, and never writes them.
- Stable note/task ids; never reuse an id across packs.
- Upgrade/uninstall only touch files still identical to what was installed.
- Validate: `dart run packages/tylog_core/bin/tylog.dart pack-validate x.tylogpack`
