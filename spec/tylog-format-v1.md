# TyLog Format v1

TyLog vaults are directories of Typst documents. Format v1 defines the
metadata contract shared by the Flutter app, the repository CLI, and external
Typst tooling. Vault generation remains `5`; the format version is carried by
each metadata value rather than by changing the vault layout.

## Documents and paths

- Notes keep importing `#import "/_system/tylog.typ" as tylog`.
- IDs are non-empty, stable strings. Producers must not silently replace an
  existing ID.
- Note and attachment paths are vault-relative, use `/` separators, and must
  not be absolute or contain `..` path segments.
- Unknown fields must be preserved where the host model supports custom
  properties and otherwise ignored by readers.

## Records

Every v1 value is a Typst dictionary containing `schema: 1`, an `entity`
matching the record type, and the fields below. Labels are intentionally
unchanged so existing Typst queries continue to work.

| Label | Entity | Required fields | Optional fields |
| --- | --- | --- | --- |
| `<tylog-note>` | `note` | `id`, `title`, `kind` | `date`, `tags`, `aliases`, `project`, `properties` |
| `<tylog-link>` | `link` | `target` | `text` |
| `<tylog-tag>` | `tag` | `name` | — |
| `<tylog-date>` | `date` | `date` | `text` |
| `<tylog-attachment>` | `attachment` | `path`, `kind` | `title` |
| `<tylog-task>` | `task` | `id`, `text`, `status`, `priority` | `project`, `scheduled`, `due`, `remind`, `timezone`, `recurrence`, `dependencies`, `assignees`, `tags`, `completed`, `properties` |

Task time tracking is carried in `properties` under the `clocked` key: a list
of `(start, end)` ISO-8601 pairs, with `end` encoded as Typst `none` while a
session is still running. It lives there rather than in its own field because `properties` is
the extension slot — a reader on an older package ignores an unknown key, while
an unknown named argument is a hard compile error.

The app writes session pairs inside the existing task properties dictionary:

```typst
properties: ("clocked": (
  ("2026-10-08T09:00:00.000Z", "2026-10-08T09:30:00.000Z"),
  ("2026-10-08T10:00:00.000Z", none),
),)
```

This adds no task field or format version. The writer preserves other
properties, removes the clocked key when no sessions remain, and collapses
exact duplicate pairs. Readers also accept the older top-level `clocked`
argument; the writer moves it into properties when edited.

The standard note kinds are `note`, `daily`, `project`, `article`, and
`research`. Other non-empty values are extensions and produce validation
warnings, not read failures.

Three `properties` keys are reserved with cross-tool meaning on imported
notes: `import_format` (`markdown`, `logseq`, or `obsidian`),
`import_source_name` (the original file name), and `import_sha256` (content
hash of the imported source; the CLI `dedupe` command treats notes sharing an
id and `import_sha256` as identical copies). Producers must not repurpose
these keys.

Task statuses are `todo`, `doing`, `done`, and `cancelled`. Priorities are
`low`, `normal`, `high`, and `urgent`. Unknown status or priority values are
validation errors because applications cannot safely infer their behaviour.

Dates are ISO 8601 calendar dates or date-times encoded as strings. Empty IDs,
unsafe paths, missing required fields, and mismatched `entity` values are
invalid.

## Compatibility

Readers must also accept generation-5 legacy values without `schema` or
`entity`. In particular, a legacy `<tylog-tag>` value is a string instead of a
dictionary. Writers emit Format v1 records. Existing note source is never
rewritten merely to upgrade metadata; it adopts v1 when edited through the
managed helper.

Metadata is introspected once per document with `query(metadata)`. Readers then
filter the returned records by the six labels. If Typst is unavailable or a
document does not compile, indexing records a warning and applies the safe
source parser so broken notes do not remove backlinks from the vault index.

## Typst API

- `tylog.note(..., body)` emits note metadata and the body. Its optional body
  transform is the only rendering hook; it does not install document-wide
  styles.
- `tylog.document(body)` owns page, font, and heading styling.
- `tylog.task(text: "...")` is canonical because task metadata requires a
  plain string. Task and tag visuals may be configured without changing their
  metadata values.

## Image attachment blocks

The app writes a standalone image as an attachment containing ordinary Typst
alignment and width, rather than extra metadata fields:

```typst
#tylog.attachment("/assets/example.png", kind: "image")[#align(center, image("/assets/example.png", width: 60%))]
```

The leading slash in this source example selects Typst vault-root lookup.
The attachment helper emits the path as passed. Width presets are 33%, 60% and 100%;
alignment is `left`, `center` or `right`. New blocks default to 60% and centre.
Older inline forms remain readable and are not rewritten until changed.

Crop writes `<original-stem>-crop-<hash8>.png` beside the original, where
`hash8` is the first eight hexadecimal characters of the cropped PNG's SHA-256.
The image reference changes to the new asset; the original remains. An existing
crop path is reused only if its bytes match; different bytes at that path cause
an error.

## Local sync safety copies

Before replacing or deleting unconfirmed local content, sync writes its bytes
under `.tylog/undo/sync-<microseconds-since-epoch>/<vault-relative-path>`.
System files and machine revision records are excluded. Content matching a
previously confirmed local hash does not need a copy. Sync directories older
than 30 days are pruned. `.tylog/undo` is local operational state and is not
synced; it is not a complete revision history.

Headerless daily repair and bulk rewrites also use `.tylog/undo/<stamp>/`
with the original paths. The 30-day pruning rule above applies to `sync-*`
directories.

Local hash receipts under `.tylog/local-history` retain the newest 32 distinct
hashes per note path, without age-based expiry; markers contain no note bytes.
The sync cursor separately retains this device's last uploaded hash. A remote
version equal to that upload or any of the retained local versions is never a
conflict. Receipts for paths absent locally and absent from the sync cursor are
removed after sync; older revisions may still supply additional ancestry proof.
