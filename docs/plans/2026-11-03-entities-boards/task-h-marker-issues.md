# Task H: marker lines as issues (@TyLog @fixit ... -> kanban card -> GitHub issue)

User request 2026-11-03: a journal line like `@TyLog @fixit describe issue` must act as a GitHub issue of project TyLog.

## Model (P1 part, no network)
- An **issue line** = any line that links a project entity (`#tylog.ref-note("<project id>")`) AND a marker page (fixit; markers come from the enrich marker config, see tool/enrich_worker.py load_markers and packages/tylog_core/lib/src/enrich.dart ~100). Plain-text marker at line start counts too (same rule as enrich).
- Scanner/index exposes `IssueRef {notePath, line, text, projectId, marker, status, githubNumber?}`. Status lives in the line itself as an inline property, written surgically: ` [#issue status: doing]` style must be chosen to compile in Typst; prefer reusing the existing task syntax: converting an issue line into a task (`applyTaskStatus`-compatible) on first status change. Decide by reading task_mutation.dart; the simplest compile-safe option wins; document it.
- Kanban (Task F) for a project shows issue cards next to task cards; marker shown as a chip (fixit = bug icon via kind registry). Drag between columns = status change via the same surgical write path.

## Decision

Keep the issue line intact and store its status in an inline Typst metadata
value, for example `#metadata(("tylog-issue-status": "doing"))`. An absent
value means `todo`. This uses a built-in Typst function and does not turn the
line into a timed task or replace its links. Status updates must replace only
this metadata value and reject a stale line rather than editing another line.

## GitHub part (P2, after OAuth)
- Project entity property `github: "owner/repo"`; marker->label map in `_system/settings/kinds.json` (`fixit -> bug`).
- Creating a GitHub issue is a Decision: card action "Send to GitHub" (or accept in review queue) -> REST `POST /repos/{o}/{r}/issues` (client from GitDoIt lib/services/github_api_service.dart) -> number written back to the line (`gh: 123`), decision logged in `_system/decisions/`.
- Refresh pulls state: closed on GitHub -> done; done in TyLog -> close via PATCH (only for issues TyLog created or linked). Comments not synced in v1.
- Offline: queued ops in `_system/` outbox, retried on next refresh.

## Tests (P1)
issue-line detection (ref-note project + marker, plain marker text, not-a-project link ignored); status write compiles; kanban scope includes issue lines of the project and its part_of descendants.
