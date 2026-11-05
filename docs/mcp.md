# TyLog MCP server

TyLog exposes a local, read-only Model Context Protocol (MCP) server over
standard input and output. It lets an MCP client search note source text and
read a note by its TyLog ID, list its backlinks and tasks, and read the latest saved health report. It does not open a network listener or change the
vault.

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
| `health_report` | None | Returns the latest dated report from `_system/health/` as JSON. Run `dart run packages/tylog_core/bin/tylog.dart vault-health <vault>` first to generate or refresh it. |

Search checks `.typ` files recursively in `daily/`, `notes/`, `projects/`,
`articles/`, `screenshots/`, and `ext/`. `get_note` reports an error when no
note has the requested ID or when more than one note has that ID. Tool errors
are returned as MCP results with `isError: true`.

Backlinks and tasks use the vault scanner’s source-based fallback, without Typst inspection; metadata generated only by Typst evaluation may be absent. Incoming and write tools are not available in this read-only slice. Health reports reflect the last run of `vault-health` and may be stale.

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
