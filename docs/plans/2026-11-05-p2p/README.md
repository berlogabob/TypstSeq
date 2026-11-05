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

For a local Android harness build, stage the isolated output in the plugin's
local JNI override (only if it does not already contain your files), then remove that override when finished:

```sh
mkdir -p packages/typst_flutter/android/src/main/jniLibs/arm64-v8a
cp packages/typst_flutter/.native-build-p2p-android/jni/arm64-v8a/libtypst_flutter.so \
  packages/typst_flutter/android/src/main/jniLibs/arm64-v8a/
cp "$HOME/Library/Android/sdk/ndk/28.2.13676358/toolchains/llvm/prebuilt/darwin-x86_64/sysroot/usr/lib/aarch64-linux-android/libc++_shared.so" \
  packages/typst_flutter/android/src/main/jniLibs/arm64-v8a/
flutter build apk --profile --dart-define=P2P_HARNESS=true \
  --target-platform android-arm64 -PtylogProfileSuffix=.profiletest
```

Install only the resulting `.profiletest` package. Remove the staged local JNI
override after the experiment before any normal build. On macOS, temporarily
point `prebuilt_lib` in `packages/typst_flutter/macos/typst_flutter.podspec` to
the isolated universal archive above, run `pod install` in `macos/`, and build
with `--dart-define=P2P_HARNESS=true`. Restore the original podspec path and run
`pod install` again before normal builds. Never copy a harness archive into
`.typst_flutter_prebuilt`.
In Settings > About, tap App version seven times and open the developer entry.
Copy the generated ticket to the receiving instance. It grants access to the
scratch text for up to five minutes; only the first connection is served.
Never put private vault contents in this experiment.

## P2P5 synthetic folder slice (2026-11-05)
The developer page can create a ticket for a generated synthetic folder: one
Typst note and two binary assets, including a 128 KiB payload. On the other
instance, choose **Receive synthetic folder** and paste the ticket. It verifies
each SHA-256 digest and restores into a fresh directory under app support; the
result shows the directory, serialized snapshot bytes, elapsed time (including connection
setup), and effective KiB/s. Both directions use the same flow. Tickets are
one-use and expire after five minutes. This is a full snapshot bounded by the
existing 1 MiB transport limit, not an incremental sync or a real-vault tool.
It does not measure CPU or battery. No new cross-device measurement is claimed;
the P2P3 no-go remains in force pending P2P5-rest.


## P2P5-rest generated-folder measurement (2026-11-05)
The developer synthetic-folder button now generates a disposable on-disk source
with 200 synthetic notes and two assets, reads it into the snapshot, and deletes
the source. The receiver checks all hashes before restoring to a fresh directory.
No existing folder or vault is read. The serialized snapshot was 438,076 bytes;
it remains subject to the 1 MiB transport ceiling.

A single profile-mode run between the Mac and Samsung A24 on the same subnet
transferred and verified exactly that snapshot in both directions. Mac → A24
was 149 ms, or 2.94 MB/s; A24 → Mac was 189 ms, or 2.32 MB/s. Rates use
serialized bytes and include connection setup, but exclude generation and
restoration. macOS `nettop` observed roughly 495 kB outgoing and 457 kB incoming
UDP on the Mac's LAN interface at the respective transfer times. The socket
view did not identify the remote IP, so a direct peer route rather than relay
is **not proven**. These small, single-shot rates are not representative vault
throughput.

Across the roughly ten-second test window, sampled process CPU averaged 8.1%
(peak 25.9%) on the A24 and 3.9% (peak 30.4%) on the Mac; samples were about
0.9 seconds apart and include setup and verification, so they do not resolve
the subsecond transfers. A24 battery reported 100% before and after (0 percentage
points); external power was connected, so this is not a battery consumption
measurement. No retry, resume, incremental transfer or user-selected folder
was exercised. The P2P3 product no-go remains in force.

To repeat the scratch-only integration test, run `python3 tool/p2p_lan_control.py
<Mac-LAN-IP>` on the Mac, then launch `flutter drive --profile` for
`integration_test/p2p_lan_measurement_test.dart` on each device with
`--driver=test_driver/integration_test.dart`, `--dart-define=P2P_HARNESS=true`
and `--dart-define=P2P_CONTROL_HOST=<Mac-LAN-IP>`. For Android pass
`-d <A24-serial> -PtylogProfileSuffix=.profiletest`; for macOS pass `-d macos`.
Use the isolated native harness builds and restore the normal build setup as
above. The coordinator forwards scratch tickets over the local network; run it
only on a trusted network. The test compares the complete received snapshot and
restores it under a temporary directory, which it deletes afterward.
