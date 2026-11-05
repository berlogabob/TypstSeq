# P2P sync inside TyLog (user 2026-11-04: work overnight on options)
Context: today sync = Nextcloud (lib/nextcloud_sync.dart), server = Fedora laptop behind Cloudflare. Earlier spike
(activity-plan lines ~150-165, docs/superpowers/plans/2026-10-20-settings-providers-sync.md): iroh 1.4 arm64 .so 5.4 MB,
Ouisync pre-1.0; sendme CLI aborts on Android outside an app ("android context was not initialized") -> needs in-app harness.
Devices: Mac, Huawei P30, Samsung A24, same Wi-Fi often; vault ~10k .typ files + assets (GBs).

## P2P1 Options report (docs/research-p2p-sync-options.md)
Compare for TyLog: iroh (+iroh-blobs/iroh-docs), Ouisync, embedded Syncthing (syncthing-android lib), libp2p,
LAN-only (mDNS + HTTPS/QUIC between TyLog instances), CRDT layers (Automerge/Yjs) vs file-level sync. Criteria: Android
SAF vault access, background limits (WorkManager), battery, NAT/relay, conflict model vs our revision envelopes and
deletion cursor rules, binary size, maturity/licence, Flutter integration (flutter_rust_bridge already used), effort.
Recommend one path + a fallback, with a staged plan. Primary sources only, cite URLs.

## P2P2 In-app iroh harness (debug-only, behind a hidden Settings > Developer switch)
Rust in the existing native crate (rebuild .so per memory: never `dart run typst_flutter:setup`; cargo ndk), Dart
bindings via flutter_rust_bridge. Two TyLog instances (Mac + Android) pair by ticket (QR/text), transfer a folder
snapshot (hashes + changed blobs) of a scratch vault, report timing/throughput/CPU. No writes to the real vault.
Tests on Mac (unit + one loopback transfer). Device runs only with the `.profiletest` suffix build; never install over
the production app.

## P2P3 Go/no-go
Using P2P1 + P2P2 numbers: write the decision and next steps into the activity plan.


## P2P2 first slice (2026-11-05)
The opt-in harness transfers one manually entered scratch text (maximum 1 MiB)
through a one-use iroh ticket. It does not open or write a vault. A Mac Rust
loopback test transferred 18 bytes in 413 ms including connection setup; this
single tiny transfer is not a throughput or CPU measurement. Flutter-to-Rust
loopback also passed on macOS and on Huawei P30 in the isolated `.profiletest`
package; no Mac-to-phone transfer was measured. P2P2-rest in the
activity plan tracks folder snapshots and the remaining measurements.

Build the Rust library with `--features p2p-harness` for each target. For
Android use the repo's cargo-ndk setup (not `typst_flutter:setup`), for example:

```sh
cd packages/typst_flutter/rust
PATH="$HOME/.cargo/bin:$PATH" \
  RUSTC="$(rustup which --toolchain stable rustc)" \
  ANDROID_NDK_HOME="$HOME/Library/Android/sdk/ndk/28.2.13676358" \
  CARGO_TARGET_DIR=../.native-build-p2p-android \
  cargo ndk -t arm64-v8a -o ../.native-build-p2p-android/jni \
  build --release --features p2p-harness
```

For macOS, from the same `rust/` directory, build both slices with the repo's
Rust 1.92 toolchain, then combine them for the existing podspec:

```sh
for target in aarch64-apple-darwin x86_64-apple-darwin; do
  if [ "$target" = aarch64-apple-darwin ]; then min=11.0; else min=10.15; fi
  MACOSX_DEPLOYMENT_TARGET="$min" CFLAGS="-mmacosx-version-min=$min" \
    RUSTC="$(rustup which --toolchain 1.92.0 rustc)" \
    CARGO_TARGET_DIR=../.native-build-p2p-1.92.0-rustup \
    rustup run 1.92.0 cargo build --release --target "$target" --features p2p-harness
done
lipo -create ../.native-build-p2p-1.92.0-rustup/{aarch64,x86_64}-apple-darwin/release/libtypst_flutter.a \
  -output ../.native-build-p2p-1.92.0-rustup/libtypst_flutter.a
```

Keep harness build outputs under `.native-build-p2p*`; never point `CARGO_TARGET_DIR`
or `cargo ndk -o` at `.typst_flutter_prebuilt`. The harness libraries are for
local debug runs only and must not replace the source-built shipping libraries.

Run `pod install` in `macos/` after changing the podspec. Run a Mac debug
build with `--dart-define=P2P_HARNESS=true`; on Android
use a profile build with `-PtylogProfileSuffix=.profiletest` and the same define.
In Settings > About, tap App version seven times and open the developer entry.
Copy the generated ticket to the receiving instance. It grants access to the
scratch text for up to five minutes; only the first connection is served.
Never put private vault contents in this experiment.
