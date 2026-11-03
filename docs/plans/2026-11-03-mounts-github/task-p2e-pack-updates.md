# P2-E: course pack updates from GitHub releases

Design change vs README: do NOT add `update` to the pack manifest (manifest.schema.json has additionalProperties:false, so older app builds would reject new packs). Keep the update source in the install record instead.

1. Install record `_system/modules/<id>.json` gains optional `source: {github: "owner/repo"}` (readers must ignore unknown keys; check module_pack.dart reader tolerates it, fix if not).
2. Settings > Modules: per installed module "Updates from GitHub" field (owner/repo); "Install from GitHub" button: owner/repo -> latestRelease -> first asset `*.tylogpack` -> download -> same install/update flow as file install (readModulePack + installModule, edited-files rule unchanged) -> record source.
3. Update check: on vault open (unawaited, at most once per 24 h) and a "Check for updates" button: latestRelease tag/asset -> read its manifest version (download asset only when the tag version > installed; compare semver of manifest `version`, tag `v1.3.0` -> 1.3.0) -> show "Update available 1.2.0 -> 1.3.0" with an Update button (reuses the existing update path with the edited-files dialog).
4. Token via githubToken() from P2-D; public repos anonymous.
5. Tests: semver compare (1.2.0 < 1.10.0, v-prefix), record round-trip keeps source and unknown keys, update check with fake GitHubClient (newer/equal/older/no asset), install-from-GitHub writes files + source. Widget tests: IO in the real async zone (tester.runAsync), pump outside, no pumpAndSettle.
Do not commit. 3-line report.
