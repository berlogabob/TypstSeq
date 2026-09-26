# P05.4b — Android profile harness

Status: host complete; device execution pending because no Android device was
connected during this run.

The isolated ORT embedder is now exposed through the existing
`typst_flutter` flutter_rust_bridge. Android builds use the pinned ORT
`2.0.0-rc.13` wrapper with its Android runtime and `tokenizers 0.23.2`; other
targets keep a small failing stub so host tooling and Dart code generation do
not require an Android runtime. The harness accepts private model and
tokenizer paths through `P05_MODEL_PATH` and `P05_TOKENIZER_PATH`, then checks
384 dimensions, finite values, and unit norm. It never logs those paths or
bundles model bytes.

Host checks:

```text
cargo check --manifest-path packages/typst_flutter/rust/Cargo.toml --offline
  Finished `dev` profile

rustup run stable cargo build --manifest-path packages/typst_flutter/rust/Cargo.toml \
  --target aarch64-linux-android --release --offline
  Finished `release` profile

flutter analyze integration_test/p05_embedding_profile_test.dart
  No issues found

flutter build apk --profile --target-platform android-arm64
  Built build/app/outputs/flutter-apk/app-profile.apk (174.9MB)
```

The release-signed profile APK contains exactly one relevant arm64 native
library, `lib/arm64-v8a/libtypst_flutter.so` (49,544,832 bytes), with no
separate `libonnxruntime.so`. Its dynamic dependencies are Android system
libraries plus `libc++_shared.so`; ORT is statically linked into the bridge.
The extracted library contains the embedder error/validation strings and ORT
symbols in its read-only data. APK inspection found no model, tokenizer, or
ONNX asset. SHA-256 values for this local build were:

```text
APK:  b46672cb329316e32acf8850f963115c25a905f8efa11e425097744bbcab9fcd
SO:   89080c90de527b034beff2c02002ce16e0c7110f1183f2228cff49a779a3ca10
```

Pending device check: install this profile APK on the A024, place the privately
verified model/tokenizer files in an app-readable directory, run
`integration_test/p05_embedding_profile_test.dart` with the two Dart defines,
and record the 384-dimensional vector agreement against the Mac spike. No
vault access is required for that run.

## Rebuilt profile artifact (2026-09-21)

`flutter build apk --profile` completed in 89.7 seconds and produced a 223.0 MB
APK at `build/app/outputs/flutter-apk/app-profile.apk`.

```text
APK: 4a3024e01e4f6146a80d7cbd33a3e55887edae3a70d27236475fd8c81f12057a
```

The artifact is ready for the pending A024 install/model-vector check; no
device was connected during this build.

## Current device gate (2026-09-22)

The A24 profile package is installed, but no private model or tokenizer files
are present in the app-readable storage, so the native vector-agreement,
latency, memory, and sustained-resume checks cannot run. The APK intentionally
contains no model bytes. P05 remains device-blocked until those private assets
are supplied.

## A24 follow-up (2026-09-23)

The six pinned model files were downloaded outside the repository and all six
SHA-256 values matched `contract.md`. The native embedding smoke passed once in
the isolated `.debug` package using app-private model/tokenizer paths. It
verified a finite, normalized 384-dimensional vector; it did not measure
profile latency, PSS, sustained resume, or compare the Android vector against
the Mac golden output.

The first `flutter drive --profile` attempt used shell-owned external-storage
files and failed at tokenizer loading. The profile integration runner then
removed the production package. The normal profile app was reinstalled and the
existing `/sdcard/TyLog` folder was reselected through SAF. No sync, import, or
conflict-resolution action was run. Do not profile against the production
package ID again; use an isolated profile package first.

## Android profile vector parity (2026-09-26)

The A24 profile run used the isolated `org.tylog.tylog.profiletest` package so
the production package and vault were not targeted. The pinned private model
and tokenizer passed hash verification before being staged in app-private
storage. The native Android result for the synthetic smoke input was compared
with the pinned Mac ORT 1.30.0 reference vector.

```text
P05_PROFILE_VECTOR_PARITY=PASS
dimension=384 finite=true normalized=true
cosine=1.000000 max_abs_difference=0.000092
acceptance: cosine >= 0.999; max_abs_difference <= 0.02
```

`flutter analyze integration_test/p05_embedding_profile_test.dart` passed.
This closes native profile vector parity only. Android exact-search timing/PSS,
sustained resume, and the 90-query judged quality pack remain open. Private
model paths, vectors, and query text are not recorded here.

## Android profile exact search and PSS (2026-09-26)

The isolated `.profiletest` package ran the actual Dart `topCosineHits` path on
250,000 deterministic synthetic 384-dimensional Float32 vectors. The run used
31 scans (one cold, 30 warm); result IDs were stable across all runs.

```text
P05_ANDROID_EXACT_SEARCH vectors=250000 dimension=384 runs=31 deterministic=true
cold=825.453 ms warm_p50=784.710 ms warm_p95=811.284 ms
max sampled TOTAL PSS=564000 kB (550.8 MiB; 24 samples)
acceptance: cold <=6000 ms; warm p95 <=3000 ms; PSS <=750 MB — PASS
```

The same updated Dart benchmark passed on macOS: cold 735.518 ms, warm p95
679.299 ms, peak RSS 566,018,048 bytes. The device harness runs the search
synthetically on the UI isolate, so its long frame is expected and is not a
UI frame acceptance run. It verifies search throughput and memory only.

This run exposed a correctness issue in `topCosineHits`: typed byte views with
a nonzero buffer offset were read from offset zero. The search now preserves
the view offset and avoids copying existing `Uint8List` vectors; a regression
test covers the offset case. P05.4c is closed. P05.4d sustained-resume testing
and the 90-query judged quality pack remain open.

## Android forced-stop resume (2026-09-26)

The A24 integration test used a dedicated `.profiletest` package and a
dedicated SQLite file under app support. The first instrumentation run stored
one bounded batch of 16 completed chunks, then exited. The package was force-
stopped with `am force-stop`; a fresh instrumentation run reopened the same
database and completed the remaining chunks.

```text
P05_RESUME_CHECKPOINT complete=16
P05_RESUME_RESULT count=128 sha256=a0c0b34b2819896451a6ab8d8a6a5944d067831b4ccfc6ca1e58fada7f51f0cc match=true
```

The hash matched an uninterrupted deterministic baseline over the same 128
chunk IDs and vectors. This validates durable batching and process-stop resume;
the embedder was deterministic synthetic code, so this does not add model
quality or long-running native inference evidence. P05.4d is closed; the 90
query judged retrieval pack remains the P05 acceptance gap.
