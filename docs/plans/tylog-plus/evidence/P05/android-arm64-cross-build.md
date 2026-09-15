# P05.4a2 — Android ARM64 feasibility

Date: 2026-09-15  
Status: PASS — cross-compilation

The isolated `tool/p05_ort_spike` was tested without adding Flutter or product
dependencies and without downloading or committing model binaries.

```bash
rustup target list --installed
cargo build --manifest-path tool/p05_ort_spike/Cargo.toml \
  --target aarch64-linux-android
```

The Android target was installed with `rustup target add` and the build used
NDK 28.2.13676358. The reproducible environment variables are:

```bash
NDK_TOOLCHAIN="$HOME/Library/Android/sdk/ndk/28.2.13676358/toolchains/llvm/prebuilt/darwin-x86_64/bin"
RUSTC_PATH="$(rustup which rustc)"
RUSTC="$RUSTC_PATH" \
CC_aarch64_linux_android="$NDK_TOOLCHAIN/aarch64-linux-android28-clang" \
CXX_aarch64_linux_android="$NDK_TOOLCHAIN/aarch64-linux-android28-clang++" \
AR_aarch64_linux_android="$NDK_TOOLCHAIN/llvm-ar" \
CARGO_TARGET_AARCH64_LINUX_ANDROID_LINKER="$NDK_TOOLCHAIN/aarch64-linux-android28-clang" \
rustup run stable cargo build \
  --manifest-path tool/p05_ort_spike/Cargo.toml \
  --target aarch64-linux-android --offline
```

The first retry exposed missing target tools (`aarch64-linux-android-ar`);
pointing `AR_aarch64_linux_android` at NDK `llvm-ar` resolved it. The final
cross-build completed successfully.

This is a compile-only result. It provides no Android model-load result and no
EN/PT/RU vector-agreement evidence because no Android device execution was
available. The existing Mac smoke remains the only runtime evidence: 384
dimensions, unit norm, finite values.
