# TyLog vault format

**Contract version: 1**

**Status: current**

**Last reviewed: 2026-11-05**

This document defines the portable, on-disk contract for a TyLog vault. It is
the reference for external article producers, bots, importers, and other
programs that read or write vault files. The app implementation remains the
compatibility authority; this document does not promise that every app build
supports every optional field described here.

Contract version 1 describes the current format. It is not the vault marker
version stored in `.tylog/settings.json`, nor the private cache/index schema
version. A producer should preserve fields it does not understand and must not
infer that an absent optional field means an empty value.

## Safety rules

- Keep all paths relative to the vault root, use `/` separators, and reject
  absolute paths, `..` traversal, and paths that escape the vault.
- A `.typ` note is valid Typst source. Write complete valid source and compile
  it with the TyLog package before publishing it.
- Preserve unknown named properties and unknown JSON keys when modifying a
  file. Prefer changing only the intended header property or task call.
- Treat `_index/` and most `_system/` data as derived or app-owned. Do not edit
  them to change note content.
- Do not overwrite a note based only on timestamps. Sync and revision history
  have their own conflict rules.
- Keep private settings such as `_system/settings/ai.local.json` local. Do not
  publish credentials, tokens, or private source text in shared bot output.

## Vault paths

The root contains `.tylog/settings.json`, the marker that identifies a TyLog
vault. Its `version` is an app compatibility gate, not this document's
contract version. Do not create or change this marker to advertise a format
revision.

Common user data paths:

| Path | Purpose |
| --- | --- |
| `daily/YYYY/MM/YYYY-MM-DD.typ` | Daily notes; date may also be in the note header. |
| `notes/<name>.typ` | General notes and entity pages. |
| `projects/<name>.typ` | Project pages; the `projects/` path alone does not define the note kind. |
| `articles/`, `research/`, `ideas/`, `events/` | Common note groupings; article and other producers may choose a different safe path. |
| `assets/` | Images, audio, PDFs, and other attached bytes. |
| `outputs/` | Generated reports and export files. |

Paths and filenames are not identities. A note's `id` is its stable identity;
renaming or moving a note should preserve that id and update references as
needed. The app may also keep dot-prefixed local state such as `.tylog/undo/`
and `.tylog/revision_prune.stamp`; those are not portable note data.

## Note source and header

Notes are UTF-8 Typst `.typ` files. The managed header is a Typst show rule
using `tylog.note` from the TyLog package. `id` and `title` are recommended;
the app can parse legacy/headerless files, but external producers should emit
the managed form.

```typst
#show: tylog.note.with(
  id: "sleep-study",
  title: "Sleep study",
  kind: "research",
  date: "2026-11-05",
  tags: ("health", "reading"),
  aliases: ("Sleep paper",),
  properties: (source: "journal", rating: 4),
)

= Sleep study

Notes and citations go here.
```

Recognized header values:

| Field | Shape and meaning |
| --- | --- |
| `id` | Stable, non-empty string. Prefer a portable slug or UUID-like value; it need not equal the filename. |
| `title` | Human-readable string. |
| `kind` | String taxonomy described below. Unknown kinds are preserved and treated as extensions. |
| `date` | Optional ISO calendar date (`YYYY-MM-DD`). Daily notes can derive this from their path when omitted. |
| `tags` | Tuple/list of strings. |
| `aliases` | Tuple/list of alternate names used for resolution and search; they do not create extra notes. |
| `project` | Optional project identifier or name retained for legacy compatibility. |
| `properties` | Open map of application or producer-specific values. Preserve keys you do not own. |

The package expands this rule into Typst metadata; the serialized internal
metadata labels and `schema` value are implementation details. Producers
should write the source form above instead of manufacturing metadata records.

### Kinds, entities, parent relations, and aliases

The standard structural kinds are `daily`, `note`, `article`, `research`,
`screenshot`, and `idea`. The standard entity-page kinds are `person`,
`organization`, `place`, `website`, `event`, and `project`. Audio notes also
use `kind: "audio"`. The vocabulary can grow; readers must preserve unfamiliar
kind strings rather than rejecting a note. A note's kind is distinct from its
folder name.

Entity parent relations are expressed in the open `properties` map as
`part_of`, containing one or more parent ids, titles, or aliases. The app
resolves those names against notes; the value is not a filesystem path.
`project` remains accepted as a legacy parent hint. Aliases are names of the
same note and should be unique enough to resolve predictably.

```typst
#show: tylog.note.with(
  id: "chapter-one",
  title: "Chapter One",
  kind: "note",
  aliases: ("Opening chapter",),
  properties: (part_of: ("the-book", "Long Book"),),
)

= Chapter One
```

### Links, tags, dates, and attachments

Use the package helpers so links and attachments remain machine-readable:

```typst
#tylog.ref-note("sleep-study")[Sleep study]
#tylog.tag("health")
#tylog.date-ref("2026-11-05")[Review date]
#tylog.attachment("assets/sleep-study.pdf", kind: "file")[Study PDF]
```

An attachment's path is vault-relative. Keep the actual bytes in the vault,
normally under `assets/`; the referenced path must remain inside the vault.
The `kind` and displayed body are descriptive metadata, not a guarantee that
the app can preview every file type. Backlinks and file references are
derived by scanning; do not maintain a duplicate backlink list.

## Tasks and task status

Tasks are Typst `tylog.task` calls embedded in a note. Give each task a stable
`id` unique within its note and preserve it when changing its text or dates.
`status` is one of `todo`, `doing`, `done`, or `cancelled`; priority is one of
`low`, `normal`, `high`, or `urgent`.

```typst
#tylog.task(
  id: "review-methods",
  text: "Review the methods section",
  status: "todo",
  priority: "normal",
  due: "2026-11-12",
  dependencies: (),
  assignees: (),
  tags: ("reading",),
  properties: (:),
)
```

Optional task fields include `project`, `scheduled`, `due`, `remind`,
`timezone`, `recurrence`, `dependencies`, `assignees`, `tags`, `completed`, and
`properties`. Date values use ISO calendar dates unless a field's semantics
require a date-time. `properties` can carry extension data, including clock
tracking. The app's parsed task index is derived from note source; do not edit
an index copy to change a task.

## Issue lines

Issues are task-like lines in notes under `daily/`, `notes/`, `projects/`,
`ideas/`, or `events/`. The app recognizes a `tylog.ref-note` link on the line
and optional Typst metadata for issue status and GitHub number. Status values
are `todo`, `doing`, `done`, and `cancelled`; the positive GitHub number is
optional. Metadata belongs on the same source line as the issue text.

```typst
- #tylog.ref-note("project-alpha")[Prepare launch] #metadata(("tylog-issue-status": "doing")) #metadata(("tylog-issue-gh": 42))
```

The app updates only the relevant inline metadata and checks that the source
line has not changed. Writers should do the same: preserve the text, link,
comments, and unrelated metadata on that line.

## `_system/` layout

`_system/` contains app support files, shared configuration, and derived
sidecars. It is not a general-purpose place for producer-owned records.

| Path | Role / ownership |
| --- | --- |
| `_system/tylog.typ` | TyLog Typst package/helper used when compiling notes. |
| `_system/theme.typ`, `_system/export.typ` | Optional presentation and export helpers. |
| `_system/bibliography.yml`, `_system/zotero.bib` | Citation data when present. |
| `_system/settings/ai.json` | Shared AI task settings; must not contain secrets. |
| `_system/settings/ai.local.json` | Device-local override; keep private and do not sync as shared settings. |
| `_system/tag-synonyms.json` | Shared tag normalization data. |
| `_system/revisions/<envelope-id>.json` | Immutable entity revision envelope files. |
| `_system/decisions/<device>.jsonl` | Append-only user decision ledger, partitioned by device. |
| `_system/enrich/mentions/<note-path-without-.typ>.json` | Derived mention and keyword suggestions for a note. |
| `_system/enrich/feedback/*.jsonl`, `_system/enrich/shown/*.jsonl` | Enrichment feedback and shown-item records. |
| `_system/health/YYYY-MM-DD.json` | Dated vault-health report. |
| `_system/health/typst-cursor.json` | Resumable cursor for bounded Typst compile checks. |
| `_index/` | Rebuildable scanner, search, and graph caches; never authoritative note data. |

There may be additional app- or feature-specific files under `_system/`.
Unknown files must be preserved. Do not copy a cache or private settings file
from another vault as if it were canonical content.

## Revisions

Revision envelopes are JSON objects stored at
`_system/revisions/<envelope-id>.json`. The current envelope has a `revision`
object and may include `history` (earlier revisions in the same publication
session), `node`, and `annotation` snapshots. The `revision` object's shape is
versioned by the app's revision model; its important history relation is
`parentRevisionId`. A parent expresses ancestry and concurrency. Wall-clock
time and the filename do not select a winning revision.

```json
{
  "revision": {
    "id": "note-example-revision-id",
    "parentRevisionId": null
  },
  "node": {
    "id": "example",
    "title": "Example"
  }
}
```

This shortened example illustrates the envelope boundary, not a complete
revision payload. A real revision includes the fields required by the app's
revision model. Readers must preserve unknown fields and ancestry. Producers
that cannot create a valid revision through the app's writer must leave
revision files untouched; editing a note source does not authorize fabricating
revision history.

## Decisions ledger

Decision files are UTF-8 JSON Lines. Each non-empty line is one independent
JSON object; append one line per human action and retain prior lines. A row has
`at` (UTC ISO-8601 timestamp), `device`, `item`, `source`, and `action`, with
optional `target` and `context`. Supported action values are `sent`, `seen`,
`added-to-today`, `scheduled`, `accepted`, `rejected`, `dismissed`, and
`ignored`.

```json
{"at":"2026-11-05T14:00:00Z","device":"phone-a","item":"daily/2026/11/2026-11-05.typ","source":"incoming","action":"accepted","target":"sleep-study"}
```

Malformed or unknown-action lines are ignored by the current reader. Writers
must emit valid JSON and a trailing newline. Do not rewrite a ledger to update
one decision; append a new decision instead.

## Enrichment sidecars

The external enrichment worker writes
`_system/enrich/mentions/<note path without .typ>.json`; it never edits note
source. The sidecar includes the source note path and `content_sha`, plus
`mentions`, `keywords`, and optionally `markers`. A mention has a surface,
type, source line number, optional hints, and an optional entity-id guess. The
guess is untrusted: the app resolves and verifies it before creating a link.
The hash is SHA-256 of the complete source after trailing whitespace is
normalized to one final newline. Stale sidecars must not be applied after note
content changes.

Feedback and shown-item logs under `_system/enrich/feedback/` and
`_system/enrich/shown/` are newline-delimited records. Their exact event
properties are feature-owned; preserve rows and append through the app's
existing writer. Enrichment output is advisory and does not itself create
links, notes, or decisions.

## Vault-health report

The read-only `tylog vault-health <vault>` check writes
`_system/health/YYYY-MM-DD.json`. It does not repair notes. A report contains
`date`, `scanned`, `typstCompile`, and `issues`. `typstCompile` reports the
bounded batch's `checked` count and `batchSize`; `issues` is a sorted list of
findings, each with a vault-relative `path` and a `code` such as
`unreadable`, `missing-note-header`, `auto-entities`, or
`typst-compile-error`. The compile cursor is operational state, not a finding.
Reports are dated snapshots; the latest filename is not a replacement for
the individual source notes.

## Compatibility and ownership summary

| Data | Authoritative? | Safe producer behavior |
| --- | --- | --- |
| `.typ` note source and referenced asset bytes | Yes | Create valid files; make surgical edits and preserve unknown source. |
| Revision envelopes | Yes, immutable history | Read and preserve; publish through a revision-aware writer. |
| Decision JSONL | Yes, append-only | Append one valid row per decision. |
| Enrichment sidecars and health reports | Derived snapshots | Read as hints/evidence; preserve unknown data; do not use as note authority. |
| `_index/` caches | No | Ignore or rebuild; never author them. |
| `.tylog/` local operational state | Usually device-local | Leave untouched unless implementing the owning app feature. |

The article pipeline and bots should pin to this document's contract version
and preserve unknown fields. They should write only files they own, validate
Typst output, and avoid modifying decision, revision, cache, or health data as
a side effect of creating an article.
