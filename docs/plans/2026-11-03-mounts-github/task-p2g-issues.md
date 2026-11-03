# P2-G: issue lines <-> GitHub issues

Spec: docs/plans/2026-11-03-entities-boards/task-h-marker-issues.md section "GitHub part". Existing: IssueRef + status metadata (`#metadata(("tylog-issue-status": X))`), board issue cards, GitHubClient.createIssue/issue/closeIssue, githubToken().

1. Project entity property `github: "owner/repo"` (header properties; editable via a small field on the entity header when kind is project; written surgically with replaceNoteProperty).
2. Marker -> label map in `_system/settings/kinds.json` entries (`"fixit": {"icon":"bug_report","label":"fixit","github_label":"bug"}`), default label = marker name.
3. Board issue card (and the issue's context menu on Today) gets "Send to GitHub" when the issue's project (or nearest part_of ancestor) has `github`: createIssue(title = plain issue text (reuse the readable-text helper from Mac fix #6), body = 'From TyLog <note path>, <date>', labels) -> write the number back into the line as `#metadata(("tylog-issue-gh": 123))` surgically next to the status metadata (same writer pattern, must compile and stay hidden in the editor like the status metadata) -> decision logged (`action: sent`, target repo#n).
4. Sync (on Board open + manual "Sync with GitHub" on the board): for issues with a number: GitHub closed -> local status done; local done and GitHub open -> closeIssue (only issues with our number). No comment sync.
5. Card shows "#123" chip linking to the issue URL.
6. Tests with fake GitHubClient: send writes number + logs decision; closed remote -> done; local done -> close called; no github property -> no Send action; written lines compile; editor hides the gh metadata (round-trip byte-exact). Widget tests: IO in tester.runAsync, pump outside, no pumpAndSettle.
Never call real GitHub in tests. Do not commit. 3-line report.
