# Pre-A24 readiness checkpoint

Date: 2026-09-21

This checkpoint records everything that can be verified without the A24 or a
real Nextcloud account.

## Host gates completed

- `flutter test --no-pub` — **748 passed, 2 skipped**.
- `flutter analyze --no-pub` — **no issues found**.
- P05 host runtime, exact-cosine, Rust/ORT cross-build, and benchmark evidence
  is recorded in `evidence/P05/`.
- P09 synthetic 10k resumable import passed; private A024 replay remains
  device/data-gated.
- P18/P19 macOS PDF reader, durable selection, reassignment, and reopen checks
  passed; Android and private-corpus checks remain.
- P20–P24 host suites passed, including hybrid retrieval, graph bounds/export,
  report workflow, and controller retry/restart-boundary matrices.
- P25 universal macOS release and launch smoke passed.

## Execute when A24 is available

1. Install the profile APK over the existing release package; do not uninstall
   or clear data.
2. Run the private A024 import rehearsal and record only aggregate counts,
   terminal manifest, duration, and validation overhead.
3. Install the private embedding model/tokenizer and run vector agreement,
   250k cold/warm search, PSS, and forced-stop resume gates.
4. Run the P12 five-minute real-editor workload: at least 1,000 frames and
   <1% of frames with build or raster duration over the observed display budget.
   Record total latency separately; see the 2026-09-23 correction in P12e/result.md.
5. Run native PDF annotation/reassignment, graph SVG share-target, and actual
   process-death reopen checks.
6. Configure the real Nextcloud account on Mac and phone, then run two-device
   restore, edit/edit conflict, attachment, and release-integrity checks.

## Explicit blockers

- The A24 is now connected. Android timing has been measured (the editor frame
  gate fails); model execution still lacks the private model/tokenizer files,
  and the installed profile has no active Android vault registry for the real
  vault rehearsal.
- No real Nextcloud endpoint/credentials are configured, so P03/P25 remain
  blocked.
- The judged 90-query pack and private corpus are not present in the repo; do
  not fabricate retrieval-quality results.


## Current release artifacts (2026-09-21)

- macOS release: 153.5 MB universal Mach-O (arm64 + x86_64), executable SHA-256
  `ec34bffdb6141bd6604620802e2feb52c267f80aeabb3ac6937040540a2b7399`.
- Android profile APK: 253.0 MB, SHA-256
  `5dfa8ee99a6d9403083d1f0cb5fb49b12ad6b52ffd6f76a9e5426bf870b00d49`.

Both builds compile the current retrieval bridge. APK installation and runtime
profiling remain pending until the A24 is available.

## A24 release launch smoke (2026-09-22)

The current profile APK installed over the release package (`org.tylog.tylog`),
launched through Android's normal activity entry point, and remained alive after
8 seconds with no Flutter fatal-error output. This is a launch check only; the
real-vault and editor frame gates remain separate.

## P09 device attempt (2026-09-22)

The profile real-vault harness was run on A24 (`000251565001005`) with the
release-signed package. It failed immediately at `VaultRegistry.active` with
`Bad state: No element`: the installed profile sandbox has no active registry
entry. The test therefore did not scan an empty vault or produce misleading
timings; P09d5 remains blocked until the production vault registry/SAF grant is
restored in that package.
