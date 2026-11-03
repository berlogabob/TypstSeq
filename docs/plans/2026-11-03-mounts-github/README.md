# P2: extension vaults (mounts) + GitHub pull/push

Parent plan: docs/plans/2026-11-03-entities-boards/README.md (primitive 3 Mount).
User decisions: GitHub pull AND push (2026-11-03). First user: PT course repo github.com/berlogabob/tylog-pack-pt-pt.

## Model
- **Mount** = a read-only (or push-enabled) source shown inside the vault under the virtual prefix `ext/<id>/`. Never copied into the synced vault; each device caches it in app support dir (`<appSupport>/mounts/<id>/`).
- Registry `_system/settings/mounts.json` (syncs, so every device knows which mounts to fetch): `[{id, name, source: {kind: "folder", path} | {kind: "github", repo: "owner/name", ref: "main", subdir?: "notes"}, push: false}]`. Tokens only in secure storage (`github_token`), never in the vault.
- Index: scanner sees `ext/<id>/...` paths through a composite storage; links by id work across vault and mounts. Notes under `ext/` open read-only unless the mount has `push: true`.
- Sync (Nextcloud) must never upload `ext/`.
- Packs (`.tylogpack`) stay install-by-copy (courses are user-editable); they gain an update channel: manifest `update: {github: "owner/repo"}` -> releases/latest asset `*.tylogpack`, semver compare, "Update available" in Settings > Modules.

## GitHub
- Auth: OAuth device flow, ported from GitDoIt `lib/services/oauth_service.dart` (client id via `--dart-define=GITHUB_CLIENT_ID`; GitDoIt's .env has one). Public repos work without a token.
- Pull: `GET /repos/{o}/{r}/commits/{ref}` -> sha; if changed, `GET /repos/{o}/{r}/zipball/{ref}` -> extract into cache (zip-slip safe, size cap), keep `sha` in cache meta.
- Push (push: true, own repos): edit -> outbox entry -> `PUT /repos/{o}/{r}/contents/{path}` with the blob sha we pulled; 409/422 sha mismatch = conflict -> keep both (`name.conflict-<device>.typ` locally) + review queue; never force.
- Issues sync (Task H P2 part) lands in P2-G.

## Tasks (in order; codex terra unless noted)
- P2-A core: `CompositeVaultStorage(main, mounts)` + mount registry model/IO + `FolderMountStorage` (read-only wrapper over LocalVaultStorage). Pure Dart in tylog_core, tests.
- P2-B app: Settings > Extensions page (add folder mount, list, remove, refresh), index through composite storage, read-only badge + editor lock for `ext/` notes, Nextcloud sync excludes `ext/`.
- P2-C GitHub client + device-flow sign-in (Settings > Connections > GitHub), token in secure storage.
- P2-D GitHub pull mount (sha check, zipball, cache, background refresh on app start + manual).
- P2-E pack update channel (manifest `update`, schema change in docs/modules/manifest.schema.json, releases/latest, Update button). Add `update` to the PT pack repo manifest.
- P2-F GitHub push (outbox, contents API, conflict keep-both + review).
- P2-G issue lines <-> GitHub issues (Task H P2 section).

User steps (only the user can do): confirm the OAuth app (reuse GitDoIt's client id or create a TyLog one with device flow enabled); publish a GitHub release of the PT pack.
