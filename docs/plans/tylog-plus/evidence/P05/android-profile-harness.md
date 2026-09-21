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
