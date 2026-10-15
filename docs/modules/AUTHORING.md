# Authoring a TyLog Module Pack

A short walkthrough for building a `.tylogpack` (data-only zip; nothing
executes). Based on `PACK-SPEC.md` and `spec/tylog-format-v1.md`.

## 1. Folder layout

Put these at the zip root:

```
my-pack/
  manifest.json
  notes/          TyLog format v1 notes (spec/tylog-format-v1.md)
  assets/         audio, images (anything)
```

- `notes/` holds one `.typ` note per lesson/entry.
- `assets/` holds audio, images, etc.
- `manifest.json` lists every other file with its SHA-256. It is itself
  excluded from the file list and hash-verified.

## 2. manifest.json

```json
{
  "schema": 1,
  "id": "pt-pt-a2b1",
  "name": "Português Europeu A2 → B1",
  "version": "1.0.0",
  "unit": "lessons",
  "files": [
    { "path": "notes/0001.typ", "sha256": "<64 hex>" },
    { "path": "assets/audio/a.mp3", "sha256": "<64 hex>" }
  ]
}
```

Rules:
- `schema` is `1`.
- `id` matches `^[a-z0-9][a-z0-9-]{0,63}$`. Pick it once and never reuse it
  across packs.
- `name` and `version` are free strings; `version` is a normal version like
  `1.0.0`.
- Optional `unit` is a string used in progress, e.g. `0/72 lessons`; omitted
  values default to `tasks`. Optional `lang` and `description` are strings.
- `files[]`: every file except the manifest, each with a `path` and a `sha256`.
  - `path` must start with `notes/` or `assets/`.
  - `sha256` is 64 lowercase hex characters.
- Unlisted files, or paths with `..` / backslashes / absolute paths, reject the
  pack.

## 3. Writing notes

Each note imports the app helper and declares a note plus one task:

```typst
#import "/_system/tylog.typ" as tylog

#show: tylog.note.with(id: "pt-pt-a2b1-0001", title: "Урок 1 — …",
  kind: "note", project: "Português", tags: ("português", "module-pt-pt-a2b1"))

#tylog.task(id: "pt-pt-a2b1-0001-task", text: "Урок 1 — …",
  due: "{{due:3}}", project: "Português")

## … note body …
```

- `id` must be non-empty and stable; never reuse an id across packs.
- Notes are self-contained: the in-app Typst compile has only
  `_system/tylog.typ`, so **no custom `#import` or layout macros**.
- `kind` is one of the standard kinds (`note`, `daily`, `project`, …); other
  values are allowed as extensions.

### Tokens (resolved at install)

- `{{id}}` — the pack id. Use it in attachment paths:

  ```typst
  #tylog.attachment("assets/modules/{{id}}/audio/a.mp3", kind: "audio")[Audio]
  ```

- `{{due:N}}` — user's start date plus N days, encoded as ISO. Put it in
  `#tylog.task(due: ...)` so the lesson appears in the agenda and calendar.
  Packs carry **offsets**, never concrete dates.

## 4. Audio

Audio lives under `assets/` and is referenced with `kind: "audio"`:

```typst
#tylog.attachment("assets/modules/{{id}}/audio/a.mp3", kind: "audio")[Audio: a]
```

For a precomputed waveform, add `assets/audio/a.mp3.peaks` alongside the
audio and list/hash it in the manifest. Encode 200 peak buckets (0–255) as
ASCII hex, two characters each (400 characters total), matching `encodePeaks`.
The app reads this sidecar before trying the audio codec; missing or invalid
sidecars fall back to audio decoding. The app never writes sidecars.

## 5. Building

Assemble the zip with a script (like `BerloPortuga/tools/pack.py`):

- Walk `notes/` and `assets/`, read each file's bytes.
- Compute `sha256` hex for each and build `manifest.json`'s `files[]`.
- Zip `manifest.json` plus every listed file (use `ZIP_STORED`; mp3 is already
  compressed).

Keep note file names stable (e.g. `notes/%04d.typ`) so ids line up.

## 6. Validating

```bash
dart run packages/tylog_core/bin/tylog.dart pack-validate x.tylogpack
```

## 7. Install, upgrade, uninstall, reschedule

Installed inside a synced vault prefix, mapping:

- `notes/x` → `projects/<id>/x`
- `assets/x` → `assets/modules/<id>/x`
- a record → `_system/modules/<id>.json` holding the installed hashes.

- **Upgrade / uninstall** only touch files that are **still identical** to what
  was installed (same hash as the record). Edited files are left alone.
- **Reschedule** (Settings > Modules) shifts the `due` of every open task of the module
  by the difference between the old and new start dates; edits to the notes are kept.
