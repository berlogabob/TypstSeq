# P2-A: composite storage + mount registry (tylog_core, pure Dart)

Read README.md in this folder first.

1. `packages/tylog_core/lib/src/mounts.dart`:
   - `class MountSource` (kind folder|github, path, repo, ref, subdir) and `class Mount {id, name, source, push}` with toJson/fromJson (unknown keys preserved), `List<Mount> parseMounts(String json)`, `String encodeMounts(List<Mount>)`; id must match `^[a-z0-9][a-z0-9-]{0,40}$`.
   - `const mountsSettingsPath = '_system/settings/mounts.json'`, `const mountPrefix = 'ext/'`.
2. `ReadOnlyVaultStorage(VaultStorage inner)`: all reads delegate; writes/deletes throw `UnsupportedError`.
3. `CompositeVaultStorage(VaultStorage main, Map<String, VaultStorage> mounts)`: paths starting `ext/<id>/` route to mount `<id>` with the prefix stripped; `list('')`/`list('ext')` show the `ext/<id>` dirs; every other path goes to main; writes to a read-only mount throw; `hash`/`stat` route the same way; `syncIdentity` = main's.
4. Tests (package:test, use the existing in-memory/LocalVaultStorage test helpers): routing for read/list/exists/stat; write to mount throws; main untouched by mount ops; registry round-trip + invalid id rejected; scanner over CompositeVaultStorage indexes `ext/<id>/notes/x.typ` and a link from a main note to a mount note's id resolves (backlinks).

Do not touch lib/ (app). Done when `cd packages/tylog_core && dart test` + `dart analyze` pass. Do not commit. 3-line report.
