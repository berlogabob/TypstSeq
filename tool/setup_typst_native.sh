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
    aarch64-apple-darwin x86_64-apple-darwin \
    aarch64-apple-ios aarch64-apple-ios-sim x86_64-apple-ios \
    aarch64-linux-android armv7-linux-androideabi \
    x86_64-linux-android i686-linux-android
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
    "$package/.typst_flutter_prebuilt/ios/typst_flutter.xcframework" \
    "$package/ios/typst_flutter/Frameworks/typst_flutter.xcframework"; do
    rm -rf "$ios_framework"
    mkdir -p "$(dirname "$ios_framework")"
    cp -R "$ios_staging" "$ios_framework"
  done
  rm -rf "$ios_staging"

  if ! command -v cargo-ndk >/dev/null 2>&1; then
    "$cargo_bin" install cargo-ndk --version 4.1.2 --locked
  fi
  android_sdk=${ANDROID_HOME:-"$HOME/Library/Android/sdk"}
  android_ndk=${ANDROID_NDK_HOME:-}
  if [ -z "$android_ndk" ]; then
    for candidate in "$android_sdk"/ndk/*; do
      [ -d "$candidate" ] && android_ndk=$candidate
    done
  fi
  if [ -z "$android_ndk" ] || [ ! -d "$android_ndk" ]; then
    echo "Android NDK is required to build typst_flutter locally." >&2
    exit 1
  fi
  echo "Building typst_flutter for Android with $(basename "$android_ndk")..."
  PATH="$HOME/.cargo/bin:$PATH" \
    ANDROID_NDK_HOME="$android_ndk" \
    CARGO_TARGET_DIR="$package/.native-build-$toolchain-rustup-android" \
    RUSTC="$rustc_bin" \
    "$cargo_bin" ndk \
      -t arm64-v8a -t armeabi-v7a -t x86_64 -t x86 \
      -o "$package/.typst_flutter_prebuilt/android" \
      build --release
fi

echo "typst_flutter native libraries are ready."
