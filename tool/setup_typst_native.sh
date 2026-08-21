#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
package="$root/packages/typst_flutter"
prebuilt="$package/.typst_flutter_prebuilt"
# Records which platforms were built from *this repo's* rust/, so a release can
# refuse to ship a downloaded upstream binary. See tool/assert_source_built.sh.
stamp="$prebuilt/.source-built"

cd "$root"
flutter pub get

# Downloads happen only here, never as a build-system side effect. This supplies
# Android/iOS and the current desktop host from the pinned upstream release.
#
# Upstream is only a *floor*. This fork adds api/markdown_import.rs, so its
# flutter_rust_bridge content hash differs from upstream's and RustLib.init()
# rejects the downloaded library outright ("Content hash Dart vs Rust out of
# sync"). Anything we actually ship has to be built below.
dart run typst_flutter:setup

# Never claim source-built when we have not built: the stamp is what the release
# gate trusts, so it starts empty every run.
rm -f "$stamp"
mark_source_built() {
  mkdir -p "$prebuilt"
  printf '%s\n' "$1" >>"$stamp"
}

# For jobs that only analyze and test. Nothing there loads the native library —
# the worker's inspector is expected to fail and fall back — so compiling Rust
# would be minutes of waste. Deliberately leaves no stamp, so a job that skips the
# build can never also ship an artifact.
if [ -n "${TYLOG_SKIP_SOURCE_BUILD:-}" ]; then
  echo "TYLOG_SKIP_SOURCE_BUILD set; downloaded libraries only, not shippable."
  exit 0
fi

toolchain=1.92.0
rustup=${RUSTUP:-$(command -v rustup || true)}
if [ -z "$rustup" ] && [ -x /opt/homebrew/opt/rustup/bin/rustup ]; then
  rustup=/opt/homebrew/opt/rustup/bin/rustup
fi

if [ -z "$rustup" ]; then
  if [ "$(uname -s)" = "Darwin" ]; then
    echo "rustup is required to build deployment-compatible macOS runtime objects." >&2
    echo "Install rustup, then run this command again." >&2
    exit 1
  fi
  # Non-Darwin without rustup keeps the old download-only behaviour, but leaves no
  # stamp — so `make verify` and the release jobs fail rather than quietly shipping
  # a library whose content hash the app will reject at startup.
  echo "rustup not found; skipping the source build." >&2
  echo "The downloaded upstream libraries are NOT shippable (see $stamp)." >&2
  echo "typst_flutter native libraries are ready (downloaded, not source-built)."
  exit 0
fi

"$rustup" toolchain install "$toolchain" --profile minimal
rustc_bin=$("$rustup" which --toolchain "$toolchain" rustc)
cargo_bin=$("$rustup" which --toolchain "$toolchain" cargo)

# Pin every rustup proxy this script's children invoke to the same toolchain.
#
# Without it a proxied `rustc`/`cargo` resolves through rustup's default, and on
# a runner whose default is due an update rustup performs that update *during*
# the build: the v0.4.0 release log shows "removing previous version of
# component rust-std" three seconds into `cargo install cargo-ndk`, and the
# compile that was running lost the host standard library mid-flight
# (`can't find crate for std`). Both the 0.3.0+94 and 0.4.0 releases died there,
# so no APK was published by either.
export RUSTUP_TOOLCHAIN="$toolchain"

"$rustup" target add --toolchain "$toolchain" \
  aarch64-linux-android armv7-linux-androideabi \
  x86_64-linux-android i686-linux-android

if [ "$(uname -s)" = "Darwin" ]; then
  "$rustup" target add --toolchain "$toolchain" \
    aarch64-apple-darwin x86_64-apple-darwin \
    aarch64-apple-ios aarch64-apple-ios-sim x86_64-apple-ios
  cd "$package/rust"
  for target in aarch64-apple-darwin x86_64-apple-darwin; do
    if [ "$target" = aarch64-apple-darwin ]; then
      deployment_target=11.0
    else
      deployment_target=10.15
    fi
    echo "Building typst_flutter for macOS $deployment_target ($target)..."
    CARGO_TARGET_DIR="$package/.native-build-$toolchain-rustup" \
      MACOSX_DEPLOYMENT_TARGET="$deployment_target" \
      CFLAGS="-mmacosx-version-min=$deployment_target" \
      RUSTC="$rustc_bin" \
      "$cargo_bin" build --release --target "$target"
  done
  mkdir -p "$prebuilt/macos"
  xcrun lipo -create \
    "$package/.native-build-$toolchain-rustup/aarch64-apple-darwin/release/libtypst_flutter.a" \
    "$package/.native-build-$toolchain-rustup/x86_64-apple-darwin/release/libtypst_flutter.a" \
    -output "$prebuilt/macos/libtypst_flutter.a"
  mark_source_built macos

  for target in aarch64-apple-ios aarch64-apple-ios-sim x86_64-apple-ios; do
    echo "Building typst_flutter for iOS 14.0 ($target)..."
    CARGO_TARGET_DIR="$package/.native-build-$toolchain-rustup" \
      IPHONEOS_DEPLOYMENT_TARGET=14.0 \
      RUSTC="$rustc_bin" \
      "$cargo_bin" build --release --target "$target"
  done
  ios_device="$package/.native-build-$toolchain-rustup/aarch64-apple-ios/release/libtypst_flutter.a"
  ios_simulator_dir="$package/.native-build-$toolchain-rustup/ios-simulator"
  mkdir -p "$ios_simulator_dir"
  ios_simulator="$ios_simulator_dir/libtypst_flutter.a"
  xcrun lipo -create \
    "$package/.native-build-$toolchain-rustup/aarch64-apple-ios-sim/release/libtypst_flutter.a" \
    "$package/.native-build-$toolchain-rustup/x86_64-apple-ios/release/libtypst_flutter.a" \
    -output "$ios_simulator"
  ios_staging="${TMPDIR:-/tmp}/typst_flutter-$$.xcframework"
  xcodebuild -create-xcframework \
    -library "$ios_device" \
    -library "$ios_simulator" \
    -output "$ios_staging"
  for ios_framework in \
    "$prebuilt/ios/typst_flutter.xcframework" \
    "$package/ios/typst_flutter/Frameworks/typst_flutter.xcframework"; do
    rm -rf "$ios_framework"
    mkdir -p "$(dirname "$ios_framework")"
    cp -R "$ios_staging" "$ios_framework"
  done
  rm -rf "$ios_staging"
  mark_source_built ios
else
  # The desktop host we can actually build for here. Bundled and dlopen'd by name
  # (packages/typst_flutter/linux/CMakeLists.txt), not linked, so a plain cdylib
  # build in place is enough.
  echo "Building typst_flutter for Linux..."
  cd "$package/rust"
  CARGO_TARGET_DIR="$package/.native-build-$toolchain-rustup-linux" \
    RUSTC="$rustc_bin" \
    "$cargo_bin" build --release
  mkdir -p "$prebuilt/linux"
  cp "$package/.native-build-$toolchain-rustup-linux/release/libtypst_flutter.so" \
    "$prebuilt/linux/libtypst_flutter.so"
  mark_source_built linux
fi

# Android, on any host. Previously this sat inside the Darwin branch, so Linux CI
# shipped the downloaded upstream .so in every published APK — a library whose
# content hash the app rejects, i.e. no Typst at all.
if [ -z "${TYLOG_SKIP_ANDROID:-}" ]; then
  cd "$package/rust"
  if ! command -v cargo-ndk >/dev/null 2>&1; then
    # Retried once: if the toolchain was mutated underneath the first attempt,
    # reinstalling it restores the host std the retry needs. A bare failure
    # here means no Typst engine in the APK, so it is worth the second try.
    if ! "$cargo_bin" install cargo-ndk --version 4.1.2 --locked; then
      echo "cargo-ndk install failed; repairing the toolchain and retrying." >&2
      "$rustup" toolchain install "$toolchain" --profile minimal --force
      "$cargo_bin" install cargo-ndk --version 4.1.2 --locked
    fi
  fi
  android_sdk=${ANDROID_HOME:-${ANDROID_SDK_ROOT:-"$HOME/Library/Android/sdk"}}
  android_ndk=${ANDROID_NDK_HOME:-${ANDROID_NDK_ROOT:-}}
  if [ -z "$android_ndk" ]; then
    for candidate in "$android_sdk"/ndk/*; do
      [ -d "$candidate" ] && android_ndk=$candidate
    done
  fi
  if [ -z "$android_ndk" ] || [ ! -d "$android_ndk" ]; then
    echo "Android NDK is required to build typst_flutter for Android." >&2
    echo "Set ANDROID_NDK_HOME, or TYLOG_SKIP_ANDROID=1 to skip." >&2
    exit 1
  fi
  echo "Building typst_flutter for Android with $(basename "$android_ndk")..."
  PATH="$HOME/.cargo/bin:$PATH" \
    ANDROID_NDK_HOME="$android_ndk" \
    CARGO_TARGET_DIR="$package/.native-build-$toolchain-rustup-android" \
    RUSTC="$rustc_bin" \
    "$cargo_bin" ndk \
      -t arm64-v8a -t armeabi-v7a -t x86_64 -t x86 \
      -o "$prebuilt/android" \
      build --release
  mark_source_built android
fi

echo "typst_flutter native libraries are ready."
echo "Source-built: $(tr '\n' ' ' <"$stamp" 2>/dev/null || echo none)"
