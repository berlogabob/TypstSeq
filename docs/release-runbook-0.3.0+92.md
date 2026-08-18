# Release runbook — TyLog 0.3.0+92

I could not run any of this: there is no shell on your Mac from this session
(the device workspace fails to start — only file transfer works) and no Flutter
toolchain anywhere I can reach. Everything below is for you to run locally.

**Do not skip step 1.** The 21 changed files have never been compiled. `make
release` runs `make test` internally, so a broken build would stop at the tests
*after* it has already bumped the version — recoverable, but messy.

## 1. Verify (the gate)

```sh
cd ~/Documents/GitHub/TypstSeq
make verify
```

`make verify` = `test-core` + `test-typst` + `flutter analyze` + `flutter test`
+ every integration test on macOS + release builds for APK and macOS.

Expect failures here to be **mechanical, not architectural** — a wrong API name
in a new test, an analyzer lint. The 12 new tests are the most likely to need a
touch, in this order:

| If it fails | Why | Fix |
|---|---|---|
| `test/voronoi_view_test.dart` | drives semantics via `tester.binding.pipelineOwner`, deprecated | keep it (it works) or move to `SemanticsBinding.instance` |
| `test/contrast_test.dart` | uses `Color.r/.g/.b` (0..1 doubles) | if your Flutter pin predates it, switch to `.value`-based channels |
| `test/property_select_chip_test.dart` | asserts the 48dp floor actually reaches the gesture area | if it fails, the WP-09 fix is wrong — not the test |
| `test/today_page_test.dart` | asserts editor ≥80% / ≥50% of viewport | check `Container` probe sizing before changing thresholds |
| `lib/controlled_editor.dart` | new `switch (value) { null || '' => … }` pattern | Dart 3 syntax; analyzer will say if the SDK pin disagrees |

Then eyeball three things a test cannot judge:

- the new highlight colour picker (Magic ▸ Highlight)
- Today with an empty agenda — the editor should own the screen
- an article row — status/relevance chips should look unchanged but hit bigger

## 2. Release

```sh
make release
```

Which does, in order: `bump-version` (0.3.0+91 → 0.3.0+92), `make test`,
`build-android`, `git add -A`, commit `Release 0.3.0+92`, tag `v0.3.0+92`,
push branch + tag. GitHub Actions then publishes:
https://github.com/berlogabob/TypstSeq/actions

`CHANGELOG.md` already carries the 0.3.0+92 entry — `git add -A` picks it up.

If you want to commit the UI work as its own commit first (recommended — it
keeps the release commit clean and makes the audit reviewable in isolation):

```sh
git add -A
git commit -m "UI audit fixes: contrast, tap targets, tokens, task-row semantics

Closes the 17 findings in docs/ui-fix-plan.md. Adds a design-token layer
(lib/widgets/constants.dart) plus two guardrail tests that keep it enforced.
See docs/ui-fix-status.md for measured before/after."
make release SKIP_BUMP=   # bump still runs; omit SKIP_BUMP to bump normally
```

## 3. If something is wrong after the tag

`make release` refuses to reuse an existing tag, so the recovery is to fix,
then run `make release` again — it bumps to +93. Don't retag.

## Rollback

Nothing here migrates data or changes the vault format (still generation 5), so
rolling back the build is sufficient; no vault surgery is needed.
