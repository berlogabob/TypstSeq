# TyLog extension packs

This note describes the current data-only module pack and extension mount
contracts. A module pack is an installable, versioned bundle of notes and
assets. A mount exposes files from a local directory or GitHub repository
under `ext/<id>/`. Neither is executable code. Runtime behavior and supported
fields are defined by the app; unknown module record fields should be
preserved when editing a record.

## Manifest

A `.tylogpack` is a ZIP containing `manifest.json` and the files it lists.
Schema version 1 requires `schema`, `id`, `name`, `version`, and `files`.
`id` matches `[a-z0-9][a-z0-9-]{0,63}` and remains stable across releases.
Each file entry has a pack-relative safe `path` under `notes/` or `assets/`
and its lowercase SHA-256 digest. Every non-directory archive file except the
manifest must be listed; missing, unlisted, unsafe, or hash-mismatched files
are rejected. Optional `unit` (default `tasks`), `lang`, and `description`
are strings; only `unit` is retained as pack metadata by the app.

```json
{
  "schema": 1,
  "id": "demo-lesson",
  "name": "Demo lessons",
  "version": "1.2.0",
  "unit": "lessons",
  "lang": "en",
  "description": "A small lesson set",
  "files": [
    { "path": "notes/lesson-1.typ", "sha256": "<64 lowercase hex characters>" },
    { "path": "assets/audio/lesson-1.mp3", "sha256": "<64 lowercase hex characters>" }
  ]
}
```

Installation maps `notes/x` to `projects/<id>/x` and `assets/x` to
`assets/modules/<id>/x`, both inside synced vault prefixes. Note templates may
use `{{id}}` and `{{due:N}}`; the installer replaces them with the pack id and
the user's chosen start date plus N days. Packs cannot supply executable
scripts, app code, or arbitrary vault paths. Upgrade and uninstall only replace
or remove files that still match the prior installed bytes; user edits and
unowned pre-existing files are kept.

## Install record

The app stores one record at `_system/modules/<id>.json`. `files` maps each
installed vault path to the SHA-256 digest of the installed bytes and is the
ownership list used for safe upgrades and uninstall. This sample shows the
record shape; `source.github` is present when a GitHub update source is set.
The app may add update-check fields, and older records may omit newer fields.

```json
{
  "id": "demo-lesson",
  "name": "Demo lessons",
  "version": "1.2.0",
  "unit": "lessons",
  "start": "2026-11-05",
  "source": { "github": "example/demo-lessons" },
  "files": {
    "projects/demo-lesson/lesson-1.typ": "<sha256 of installed bytes>",
    "assets/modules/demo-lesson/audio/lesson-1.mp3": "<sha256 of installed bytes>"
  }
}
```

Treat `_system/modules/` as app-owned metadata. Do not edit its `files` map to
change note contents; edit the installed note itself. Preserve unrecognized
record keys when updating metadata.

## Update channel

An update source is a GitHub `owner/repository` saved at
`source.github`. The repository's latest GitHub Release must have a
`.tylogpack` asset whose manifest has the installed pack's stable `id`; the
manifest `version` is compared with the installed `version`. The app checks
at most once per seven days and stores `updateAttemptedAt`, `updateCheckedAt`,
and `updateAvailableVersion` in the install record as applicable. Publishing
an update means attaching the new validated pack to a GitHub Release. A repo
branch or arbitrary URL is not the module update channel. The pack itself
does not authenticate its author: users should install from repositories they
trust.

## Mounts

Mount settings are a JSON array in `_system/settings/mounts.json`. A mount has
an `id` matching `[a-z0-9][a-z0-9-]{0,40}`, a display `name`, a `source`, and a
`push` boolean. Mount ids are unique within the workspace and form the first
segment in `ext/<id>/<relative-path>`.

```json
[
  {
    "id": "reference",
    "name": "Reference folder",
    "source": { "kind": "folder", "path": "/path/to/reference" },
    "push": false
  },
  {
    "id": "team-notes",
    "name": "Team notes",
    "source": {
      "kind": "github",
      "repo": "example/team-notes",
      "ref": "main",
      "subdir": "published"
    },
    "push": true
  }
]
```

`folder` mounts read from a local directory. `github` mounts fetch the selected
repository ref and optional subdirectory into an app cache; `ref` should be a
branch or tag. GitHub mounts are read-only when `push` is false. Only GitHub
mounts may enable push. The GitHub token is held by the app's credential
store, not in the mount JSON or vault.

## Write boundaries

- Module packs can create only listed note and asset files at their mapped
  install paths, plus their app-owned install record. The manifest cannot
  grant additional write permissions.
- A read-only mount can be browsed and indexed, but edits are rejected. Local
  folder mounts have no push mode.
- A GitHub mount with `push: true` accepts edits only below its own
  `ext/<id>/` prefix. A save queues that relative file in the app-local GitHub
  outbox; it does not write mount metadata or arbitrary vault files. The app
  later commits through GitHub using the saved base revision and reports
  conflicts for explicit resolution.
- Mount settings are app configuration, module install records are app-owned,
  and `_index/` is derived data. External pack content cannot write any of
  these or other vault paths.

The mount record currently accepts extra JSON keys and preserves them through
read/write. The fields above are the supported contract; extra keys do not
grant capabilities.
