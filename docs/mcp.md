# TyLog MCP server

TyLog exposes a local Model Context Protocol (MCP) server over
standard input and output. It lets an MCP client search note source text and
read a note by its TyLog ID, list its backlinks and tasks, append text to an existing daily note, add tasks to notes, and read or refresh the vault health report. It does not open a network listener. Refreshing a health report writes report and scan cursor files under `_system/health/`.

## Requirements and launch command

The server requires Dart and a valid TyLog vault (including
`.tylog/settings.json`). From a checkout of this repository, launch it with:

```sh
dart run /absolute/path/to/TypstSeq/packages/tylog_core/bin/tylog.dart \
  mcp /absolute/path/to/vault
```

Replace both paths with local absolute paths. The MCP client starts this
process and exchanges newline-delimited JSON-RPC messages over stdin/stdout;
do not add logging or other output to stdout when running the server. The
process exits when its input closes. A missing or invalid vault marker causes
startup to fail.

## Available tools

| Tool | Required argument | Result |
| --- | --- | --- |
| `search` | `query`: non-empty string | Case-insensitive search of note source text. Returns up to 50 matches sorted by vault-relative path; each match contains `id`, `title`, and `path`. |
| `get_note` | `id`: non-empty string | Returns the complete source of the note with that TyLog ID. |
| `backlinks` | `id`: non-empty string | Returns linking notes as JSON objects with `id`, `title`, and `path`. The target ID must be unique. |
| `list_tasks` | None | Returns tasks as JSON objects, including their note paths, statuses, and dates. |
| `add_task` | `id`: unique note ID; `text`: non-empty single-line string | Adds a task above the generated entities block in an existing note, and records a decision. Returns the note path and new task ID. |
| `daily_append` | `date`: YYYY-MM-DD; `text`: non-empty single-line string | Appends literal text above the generated entities block in the existing canonical daily note, and records a decision. Returns the note path. |
| `incoming_list` | None | Returns vault notes with new attention, sorted by path, with `id`, `title`, `path`, `kind`, and `date` (which may be null). |
| `propose_mention` | `id`: unique daily note ID; `surface`: non-empty single-line text; `type`: person, place, organization, project, or event; `line`: 1-based line number | Queues a mention present on that line in the Incoming suggestions sidecar and records a decision. Returns the note and proposal paths. |
| `health_report` | Optional `refresh`: boolean | Returns the latest dated report from `_system/health/` as JSON. Set `refresh` to `true` to scan the vault and generate a fresh report. |

Search checks `.typ` files recursively in `daily/`, `notes/`, `projects/`,
`articles/`, `screenshots/`, and `ext/`. `get_note` reports an error when no
note has the requested ID or when more than one note has that ID. Tool errors
are returned as MCP results with `isError: true`.

Backlinks, tasks, and incoming notes use the vault scanner’s source-based fallback, without Typst inspection; metadata generated only by Typst evaluation may be absent. `incoming_list` uses the app's attention rules, including legacy screenshot, idea, and audio defaults. It does not include the app's separate suggestion, audio proposal, OCR, booking, or health review queues. The daily note must already exist with matching note metadata. `daily_append` and `add_task` reject control characters and non-note targets, and each writes one decision to `_system/decisions/mcp.jsonl`. Note and ledger writes are separate; a ledger I/O failure after the note write is reported as an error and requires checking the note before retrying. Without `refresh`, health reports may be stale.

`propose_mention` never edits the note. It preserves existing suggestions and refuses stale or invalid sidecars; the Incoming queue currently supports suggestions for daily notes. The app resolves suggestions using its normal rules, including automatic linking of confident matches when leaving a daily note. A ledger failure after the sidecar write is reported as an error; check the sidecar before retrying. The enrichment worker may subsequently replace the sidecar.

## Claude Code

Register the server for your user from any directory. Replace the checkout and
vault paths with absolute local paths:

```sh
claude mcp add --transport stdio --scope user tylog -- \
  dart run /absolute/path/to/TypstSeq/packages/tylog_core/bin/tylog.dart \
  mcp /absolute/path/to/vault
```

Alternatively, add the following to a project-root `.mcp.json` to share the
configuration with that project. Project-scoped MCP servers require approval
the first time Claude Code uses them.

```json
{
  "mcpServers": {
    "tylog": {
      "type": "stdio",
      "command": "dart",
      "args": [
        "run",
        "/absolute/path/to/TypstSeq/packages/tylog_core/bin/tylog.dart",
        "mcp",
        "/absolute/path/to/vault"
      ]
    }
  }
}
```

Use `claude mcp list` to check the connection, or `/mcp` inside Claude Code to
inspect the server and its tools.

## Hermes Agent

Add the server under `mcp_servers` in `~/.hermes/config.yaml`. Replace the
paths with absolute local paths:

```yaml
mcp_servers:
  tylog:
    command: dart
    args:
      - run
      - /absolute/path/to/TypstSeq/packages/tylog_core/bin/tylog.dart
      - mcp
      - /absolute/path/to/vault
```

Hermes starts local stdio servers as subprocesses. Start a new Hermes session
or reload its MCP connections after editing the config, then check its startup
status for the TyLog server and its tools.

## References

- [Claude Code MCP setup](https://code.claude.com/docs/en/mcp)
- [Hermes Agent MCP setup](https://github.com/NousResearch/hermes-agent/blob/main/website/docs/user-guide/features/mcp.md)
