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

The standard note kinds are `note`, `daily`, `project`, `article`, and
`research`. Other non-empty values are extensions and produce validation
warnings, not read failures.

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

