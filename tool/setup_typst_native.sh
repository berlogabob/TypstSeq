#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
package="$root/packages/typst_flutter"

cd "$root"
flutter pub get

# Downloads happen only here, never as a build-system side effect. This supplies
# Android/iOS and the current desktop host from the pinned upstream release.
dart run typst_flutter:setup

if [ "$(uname -s)" = "Darwin" ]; then
  rustup=${RUSTUP:-$(command -v rustup || true)}
  if [ -z "$rustup" ] && [ -x /opt/homebrew/opt/rustup/bin/rustup ]; then
    rustup=/opt/homebrew/opt/rustup/bin/rustup
  fi
  if [ -z "$rustup" ]; then
    echo "rustup is required to build deployment-compatible macOS runtime objects." >&2
    echo "Install rustup, then run this command again." >&2
    exit 1
  fi
  toolchain=1.92.0
  "$rustup" toolchain install "$toolchain" --profile minimal
  rustc_bin=$("$rustup" which --toolchain "$toolchain" rustc)
  cargo_bin=$("$rustup" which --toolchain "$toolchain" cargo)
  "$rustup" target add --toolchain "$toolchain" \
    aarch64-apple-darwin x86_64-apple-darwin
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
  mkdir -p "$package/.typst_flutter_prebuilt/macos"
  xcrun lipo -create \
    "$package/.native-build-$toolchain-rustup/aarch64-apple-darwin/release/libtypst_flutter.a" \
    "$package/.native-build-$toolchain-rustup/x86_64-apple-darwin/release/libtypst_flutter.a" \
    -output "$package/.typst_flutter_prebuilt/macos/libtypst_flutter.a"
fi

echo "typst_flutter native libraries are ready."
