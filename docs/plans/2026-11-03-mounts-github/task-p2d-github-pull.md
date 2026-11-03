# P2-D (+C2): GitHub repo as an extension (pull)

Uses lib/github/github_client.dart + github_auth.dart (P2-C) and the mounts pipeline (P2-B: WorkspaceController.reloadMounts, github mounts read `<appSupport>/mounts/<id>/`).

1. C2 token source: `Future<String?> githubToken()` = secure-storage `github_token` if present, else on desktop run `gh auth token` (Process.run, 5 s timeout, ignore failures), else null. Public repos work with null.
2. `MountFetcher.refresh(Mount m)`: for kind github: `commitSha(repo, ref)`; if equal to `<cache>/<id>/.tylog-mount.json`.sha -> no-op; else `downloadZipball`, extract to `<cache>/<id>.tmp/` (strip GitHub's top-level folder, honour `subdir`, zip-slip guard, skip files > 20 MB, total cap 500 MB), write meta {sha, fetchedAt}, atomic swap tmp -> `<id>/`, then reloadMounts(). Errors -> status line, keep old cache.
3. When: on vault open (after mounts load, unawaited, never blocks startup; at most once per 6 h per mount unless manual), and a Refresh button per mount on the Extensions page.
4. Extensions page: enable "Add GitHub repo": dialog with `owner/repo`, optional ref (default branch from `GET /repos/{o}/{r}`), optional subdir; validates repo exists; adds mount `{kind: github, repo, ref, subdir}`, then refresh. Shows sha short + fetched time. Android too.
5. Tests: fetcher with fake GitHubClient (sha unchanged no-op, changed -> swap, zip-slip rejected, failure keeps old cache); token fallback order (fake Process runner); page add-github dialog writes mounts.json. Widget tests: run controller/IO work in the real async zone (tester.runAsync), pump outside, no pumpAndSettle.

Manual check (Claude): add `berlogabob/tylog-pack-pt-pt` (public) with subdir `typst` on the scratch vault, see lessons indexed under ext/.
Do not commit. 3-line report.
