# P2-F: push edits back to GitHub (mounts with push: true)

1. Mount `push: true` only for github mounts; Extensions page toggle "Allow editing (push to GitHub)" enabled only when the token can push (`GET /repos/{o}/{r}` -> permissions.push).
2. Notes under such a mount are editable. Saving writes the file into the local mount cache AND appends an outbox entry `_system/outbox/github/<mount>/<uuid>.json` {path, baseSha (blob sha from the pulled tree or last push), message, at, device}. Outbox lives in the synced vault? NO: per-device app support dir (tokens/devices differ); conflicts surface per device.
3. Pusher (on save debounce 30 s, app resume, manual "Push now"): for each entry in order: `putContent(repo, subdir+path, bytes, message 'TyLog: edit <path>', sha: baseSha, branch: ref)`; success -> new sha stored in cache meta map {path: blobSha}, entry removed; `GitHubConflict` -> fetch remote content, write it as `<name>.remote.typ` next to the local file in the cache, keep the local edit, mark entry conflicted, show in Incoming/review queue "GitHub conflict: <path>" with actions Keep mine (push with remote sha) / Take theirs (overwrite local, drop entry). Never force, never delete remote files in v1.
4. Pull (P2-D) must not overwrite files with pending outbox entries (merge rule: skip those paths, keep local).
5. Blob shas: P2-D extraction must record per-file git blob sha (sha1 of 'blob <len>\0' + bytes) in cache meta so baseSha is known without extra API calls.
6. Tests: blob sha matches git (`git hash-object`); save -> outbox -> push success updates sha; 409 -> conflict files + review item; Keep mine/Take theirs; pull skips pending paths. Fake GitHubClient. Widget tests: IO in tester.runAsync, pump outside, no pumpAndSettle.
Do not commit/push. 3-line report.
