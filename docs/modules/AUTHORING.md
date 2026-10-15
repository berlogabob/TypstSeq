# Authoring a TyLog Module Pack

A practical guide for building a `.tylogpack` (a data-only zip; nothing in a
pack executes). Based on `PACK-SPEC.md`, `manifest.schema.json`, the example
pack [tylog-pack-pt-pt](https://github.com/berlogabob/tylog-pack-pt-pt), and
`packages/tylog_core/lib/src/module_pack.dart`.

## What a pack is

A `.tylogpack` is a zip with three parts:

```
manifest.json
notes/**.typ     TyLog format v1 notes (spec/tylog-format-v1.md)
assets/**        audio, images (anything)
```

- `notes/` holds one `.typ` note per lesson/entry.
- `assets/` holds audio, images, etc.
- `manifest.json` lists every other file with its SHA-256. It is itself
  excluded from the file list and hash-verified.

Install maps paths (inside a synced vault prefix only):

- `notes/x` → `projects/<id>/x`
- `assets/x` → `assets/modules/<id>/x`
- a record → `_system/modules/<id>.json` holding the installed hashes.

## 10-minute quickstart

Build this tiny pack:

```
demo-0001/
  manifest.json
  notes/0001.typ
```

`manifest.json` (note the optional `unit` field):

```json
{
  "schema": 1,
  "id": "demo-0001",
  "name": "Demo",
  "version": "1.0.0",
  "unit": "lessons",
  "files": [
    { "path": "notes/0001.typ", "sha256": "<64 hex>" }
  ]
}
```

`notes/0001.typ`:

```typst
#import "/_system/tylog.typ" as tylog

#show: tylog.note.with(id: "demo-0001-0001", title: "Lesson 1",
  kind: "note", project: "Demo", tags: ("demo", "module-demo-0001"))

#tylog.task(id: "demo-0001-0001-task", text: "Lesson 1",
  due: "{{due:1}}", project: "Demo")

## Hello — the first lesson.
```

Build it with a 15-line script that hashes every file and zips:

```python
#!/usr/bin/env python3
import hashlib, json, os, zipfile
ROOT, OUT = "demo-0001", "dist/demo-0001.tylogpack"
files = {}  # pack path (relative to ROOT, e.g. notes/0001.typ) -> bytes
for top in ("notes", "assets"):
    for dirpath, _, names in os.walk(os.path.join(ROOT, top)):
        for n in sorted(names):
            full = os.path.join(dirpath, n)
            files[os.path.relpath(full, ROOT)] = open(full, "rb").read()
manifest = {"schema": 1, "id": "demo-0001", "name": "Demo",
            "version": "1.0.0", "unit": "lessons",
            "files": [{"path": p, "sha256": hashlib.sha256(b).hexdigest()}
                      for p, b in sorted(files.items())]}
os.makedirs("dist", exist_ok=True)
with zipfile.ZipFile(OUT, "w", zipfile.ZIP_STORED) as z:  # mp3 is already compressed
    z.writestr("manifest.json", json.dumps(manifest, indent=1))
    for p, b in sorted(files.items()): z.writestr(p, b)
```

Run it, then validate:

```bash
python3 build.py
dart run packages/tylog_core/bin/tylog.dart pack-validate dist/demo-0001.tylogpack
```

Install it in TyLog: Settings > Modules > Install from file.

## manifest.json

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
  values default to `tasks`. Optional `lang` and `description` are informational strings the app ignores.
- `files[]`: every file except the manifest, each with a `path` and a `sha256`.
  - `path` must start with `notes/` or `assets/`.
  - `sha256` is 64 lowercase hex characters.
- Unlisted files, or paths with `..` / backslashes / absolute paths, reject the
  pack.

## Writing notes

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

## Results tracking

The Modules sheet reads progress from the owned notes. It counts each
`#tylog.task` as one lesson and marks a lesson done when its `status` is `done`.
That gives the `done/total` progress (e.g. `3/72 lessons`).

Add a `score::` line to report a result; the Modules sheet lists it:

```
score:: 32/40
```

The line must match `score:: <n>/<m>` on its own line (leading spaces allowed).

## Audio

Audio lives under `assets/` and is referenced with `kind: "audio"`:

```typst
#tylog.attachment("assets/modules/{{id}}/audio/a.mp3", kind: "audio")[Audio: a]
```

### Waveform sidecars (optional)

For a precomputed waveform, add a `.peaks` sidecar next to each audio file:
`assets/audio/a.mp3.peaks` sits beside `assets/audio/a.mp3`, and you list and
hash it in the manifest like any other file.

The sidecar holds 200 peak buckets. Each bucket is scaled 0–255 relative to the
loudest bucket, encoded as ASCII hex, two characters per bucket (200 buckets =
400 characters). The app reads the sidecar before trying the audio codec; a
missing or invalid sidecar falls back to audio decoding. The app never writes
sidecars. This is the ffmpeg-based function the example pack uses:

```python
def peaks_hex(mp3, buckets=200):
    """200 loudness buckets (0-255, hex pairs) like a Reaper .reapeaks sidecar."""
    import array, subprocess
    raw = subprocess.run(["ffmpeg", "-v", "error", "-i", mp3, "-ac", "1", "-ar", "8000", "-f", "s16le", "-"],
                     capture_output=True, check=True).stdout
    pcm = array.array("h"); pcm.frombytes(raw[: len(raw) // 2 * 2])
    n = min(buckets, len(pcm))
    if n == 0: return ""
    bars = [0] * n
    for i, v in enumerate(pcm):
        b = i * n // len(pcm); v = abs(v)
        if v > bars[b]: bars[b] = v
    top = max(bars) or 1
    return "".join("%02x" % round(v * 255 / top) for v in bars)
```

## The `unit` field (optional)

`unit` labels the progress number shown in Settings > Modules as `done/total`.
It defaults to `tasks`, so a pack without it reads e.g. `3/72 tasks`. Set it to
something like `lessons` to read `3/72 lessons`. The install record retains the
`unit`; older records default to `tasks`.

## Building

Assemble the zip with a script (like `tools/pack.py` in
[tylog-pack-pt-pt](https://github.com/berlogabob/tylog-pack-pt-pt)):

- Walk `notes/` and `assets/`, read each file's bytes.
- Compute `sha256` hex for each and build `manifest.json`'s `files[]`.
- Zip `manifest.json` plus every listed file (use `ZIP_STORED`; mp3 is already
  compressed).

Keep note file names stable (e.g. `notes/%04d.typ`) so ids line up.

## Validating

```bash
dart run packages/tylog_core/bin/tylog.dart pack-validate x.tylogpack
```

## Install, upgrade, uninstall, reschedule

Files land in the synced vault prefixes listed above.

- **Upgrade / Update** only touches files that are still identical to what was
  installed (same hash as the record). Edited files are left alone. Update
  removes files that the new version dropped, but only if they are still
  unedited.
- **Uninstall** deletes only files still identical to what was installed;
  edited files are kept. An edited note is never marked untouched, so Uninstall
  keeps it.
- **Reschedule** (Settings > Modules) shifts the `due` of every open (not
  done, not cancelled) task of the module by the difference between the old and
  new start dates. Only date literals change; edits to the notes are kept. A
  pristine note's new bytes become its recorded version, while an edited note
  stays marked edited.

## Publishing

Attach the `.tylogpack` to a GitHub release. Readers install it from the
downloaded file via Settings > Modules > Install from file. The worked example
with full tooling lives at [tylog-pack-pt-pt](https://github.com/berlogabob/tylog-pack-pt-pt).

## Common mistakes

- Adding a custom `#import` or layout macro in a note — the in-app compile has
  only `_system/tylog.typ`, so notes must be self-contained.
- Reusing an `id` across packs — pick one and never reuse it.
- Referencing paths outside `notes/` and `assets/` — every listed path must
  start with `notes/` or `assets/`.
- Forgetting to list a file (including a `.peaks` sidecar) — every file except
  the manifest must be listed and hash-verified, or the pack is rejected.
