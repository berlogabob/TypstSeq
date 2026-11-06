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
<Mac-LAN-IP>` on the Mac, then run
`flutter test integration_test/p2p_lan_measurement_test.dart --no-uninstall`
on each device with `--dart-define=P2P_HARNESS=true` and
`--dart-define=P2P_CONTROL_HOST=<Mac-LAN-IP>`. For Android pass
`-d <device-id> -PtylogProfileSuffix=.profiletest`. Use isolated native harness
builds and restore the normal build setup as above. Never use `flutter drive`
on a phone containing the real app: it can uninstall that app. The coordinator
forwards scratch tickets over the local network; run it only on a trusted
network. The test compares the complete received snapshot and restores it under
a temporary directory, which it deletes afterward.

## P2P5-rest-rest changed synthetic blob slice (2026-11-05)
The developer harness can create a ticket for one modified synthetic note.
Only changed file data is sent against the deterministic generated 200-note
baseline; the receiver regenerates that baseline, checks its SHA-256, validates
each resulting file hash, and restores the complete result in a fresh app-owned
directory. Use **Create changed scratch ticket** and **Receive changed scratch
folder** on the two peers. The baseline must match exactly. The experiment does
not support adding or deleting paths, actual user folders, retry or resume. It
is not a synchronization or reconciliation protocol, and retains the native
1 MiB message limit. Tests exercise reconstruction and baseline mismatch; no
new cross-device throughput, CPU, route or battery-consumption measurements
were made for this slice. On the A24, battery service reported AC power and
100% at inspection; this is not an unplugged measurement. The P2P3 no-go
remains until the outstanding gates in P2P5-rest-rest-rest are met.

## P2P6-rest real snapshot (2026-11-05)
An explicitly authorized APFS clone of the Mac vault was made read-only in the
scratchpad and sent to the P30 test app's private storage. It contained 25,206
files and 2,461,600,858 bytes. The existing folder protocol checks the SHA-256
of every received file, and checks already-present files before skipping them.
The sender reported completion at 16:39:14, after the 16:33:07 receiver start:
367 seconds including an intentional receiver kill, an idle wait, a new sender
ticket and reconnection, equivalent to 6.71 MB/s of snapshot content over the
whole elapsed interval. This is not an exact network-byte rate. A fresh-ticket
repeat re-read the destination against the complete manifest in 33.667 seconds
and reported zero bytes needed, confirming every manifest file already matched.

After killing the receiver at 16:34:14, reuse of the original ticket remained
idle for approximately a minute. Restarting the sender and using a new ticket
resumed the same destination at 16:35:44 and completed. This does not prove
same-ticket process restart works; it needs investigation. The route could not
be distinguished as direct or relay from the available socket information.
No nettop was used. The received copy is app-private; opening and indexing it
in TyLog remain unmeasured. This experiment does not establish product sync,
conflict, deletion or lifecycle safety, and P2P3's no-go remains.

P30 process CPU samples averaged 76.1% (peak 185%, 33 samples including the
interruption); Mac sender samples after restart averaged 29.6% (peak 85.5%, 27
samples). These are approximately ten-second samples, with 100% representing
one core, not energy measurements. Batterystats history's last recorded charge value
was the same 24 mAh entry before and after (it did not update during the run);
Battery Service reported 24,000 µAh and 80% before and after,
with AC connected and status not charging. This zero delta is not a meaningful
unplugged battery-consumption measurement. The production install time remained
2026-11-05 15:27:02 before and after; only the `.profiletest` release APK was
installed or launched.

The reusable local runner is `tool/p2p6/main.dart` with
`tool/p2p6/coordinator.py`. Build the isolated native libraries as described
above, with release Flutter builds and the source clone passed to macOS as
`--dart-define=P2P_SOURCE=<absolute-clone-path>`. The release Android build
accepts `-PtylogProfileSuffix=.profiletest` and checks the package at runtime.
Run the coordinator on the Mac, forward port 47993 with `adb reverse`, launch
Mac first and wait for `ticket ready`, then launch the test APK. The receiver
uses `p2p6-received` under its own application support directory and reuses
verified files there; it does not delete extra destination files. Stop and
restart both peers with a fresh ticket to retry a stalled process restart.
Only use a source the user has explicitly authorized; do not grant the test
app access to the original vault. Tickets must stay local and private. Harness
libraries are isolated build outputs and must never be copied into
`.typst_flutter_prebuilt`.

## P2P6-rest-rest received-copy opening (2026-11-05)
The already verified P30 app-private copy was registered as an app-local vault
with no cloud configuration and opened in the `.profiletest` app. On a cold
start, `TYLOG_STARTUP` recorded `open-start` at 365 ms, `today-readable` at
583 ms, and `index-published` at 30,724 ms: 30.359 s from open to publication.
The index event reported 10,085 notes, a 29.038 s indexing duration, source
`scan`, and four parsed notes. This used the index already present in the
snapshot; it is not a clean-index benchmark. The app was left in the foreground
with this copy open for visual review.

Before and after this opening, batterystats history's last charge entry was
23 mAh and Battery Service reported 23,000 µAh, 80%, AC connected and status
not charging. The zero observed delta is not an unplugged consumption measure.
The production installation's first-install timestamp remained
2026-11-05 15:27:02. The earlier transfer did not log iroh's selected path, so
neither direct LAN nor relay is established for it. Its temporary source clone
was removed after the transfer; no new copy of the original vault was made.
Same-ticket restart, route evidence, unplugged battery consumption and the
remaining product safety gates remain outstanding; the P2P3 no-go still holds.

For this isolated opening, build `tool/p2p6/open_main.dart` as a release APK
with `-PtylogProfileSuffix=.profiletest` and the Android harness library staged
as above. The entry point checks the native `.profiletest` guard, requires the
existing `p2p6-received` directory and selects it without removing other vault
registrations. It must only be installed over the isolated test package.

## P2P6-rest-rest-rest restart investigation (2026-11-05)
The folder sender previously waited for the active connection to finish before
accepting another. A receiver process disappearing can therefore leave a new
connection waiting behind the old one until the transport detects its loss.
The harness now accepts a replacement connection and closes the old one. A
synthetic loopback test holds the first connection open after reading the
manifest and verifies a second receiver completes with the same ticket; it
failed by timeout before the change. This reproduces a plausible stall, not a
measurement of the earlier phone failure. An actual process-kill retry, path
instrumentation and unplugged battery measurement remain in the follow-up.
The P30 reported AC power, so no battery consumption is claimed. The Mac GUI
was locked and was not used. P2P3 remains no-go.

## P2P6-rest-rest-rest-rest selected-path diagnostic (2026-11-05)
The folder receiver samples iroh's selected application-data path every 500 ms
and logs changes as `P2P6_SELECTED_PATH direct-ip`, `relay`, `other`, or
`unknown`. It logs no addresses or tickets. Sampling can miss shorter path
changes; a direct IP path is not by itself proof that the IP route was LAN.
A local loopback regression selected direct IP and the existing same-ticket
replacement test completed. This does not establish the earlier transfer's
route or demonstrate a phone process restart.

The P30 was reachable via adb, but its current package list did not contain
`org.tylog.tylog`, and its required first-install timestamp could not be read.
No install, launch, kill or transfer was attempted on the device during this
slice. Battery Service reported AC powered and 80%; no unplugged consumption
measurement was possible. Resolve the production package state before further
device work. The Mac GUI was locked and not used. P2P3 remains no-go.

## P2P5-rest-rest-rest transfer counters (2026-11-06)
Successful folder receives now log `P2P6_TRANSFER_METRICS` with established
connections, retries (established connections after the first), blob requests,
and resumed bytes (the sum of requested partial-file offsets). Requests and
offsets include repeated attempts, so they are not counts of unique changed
files or unique bytes saved. Failed connection attempts and transfers that never
complete are not summarized. The existing success line reports received payload
bytes and elapsed time; neither is total network traffic. These counters expose
retry and resume behavior for the existing isolated folder runner without
logging paths, addresses or tickets.

The P30 was visible over adb, but the production package was absent from the
package list and its required first-install timestamp could not be verified.
No device install or launch was attempted. The locked Mac GUI was not used.
No new cross-device, route, CPU or battery measurements are claimed; P2P3
remains no-go. The remaining measurements and safety gates are tracked in
P2P5-rest-rest-rest-rest. The counter unit test passed; the existing native
reconnection test failed because loopback did not select a direct IP path
within five seconds on this host, so it did not verify a transfer in this run.

## P2P5-rest-rest-rest-rest P30 measurement preparation (2026-11-06)
`tool/p2p_measure.py` takes read-only snapshots around a transfer in the running
`.profiletest` process. It checks the production package's required
`firstInstallTime` before and after each snapshot and refuses to sample if it is
missing or different. With the isolated app already running, use:

```sh
python3 tool/p2p_measure.py begin /tmp/p2p-measure.json
# Run one transfer, without restarting the test process.
python3 tool/p2p_measure.py end /tmp/p2p-measure.json
```

Use a fresh state path for each interval. Output includes elapsed time, process
CPU seconds and average CPU as a percentage of one core, battery charge-counter
delta in microamp-hours, and Android battery status and AC/USB/wireless power
states at both ends (status 2 means charging, 3 discharging, 4 not charging,
5 full). The counter can update coarsely or be unavailable; a zero delta or
an externally powered run does not establish battery consumption. Sampling
includes time between the snapshots, not just transfer activity. A restarted
process, missing counter, inaccessible `/proc`, or failed timestamp check aborts
rather than reporting a misleading result. The script neither installs nor
launches packages. It does not measure route, network bytes, changed blobs,
retries, or resume; use the existing transfer logs for their available counters.

On this run the P30 was visible by adb but `org.tylog.tylog` was absent from
its package list, so the required timestamp could not be verified. The sampler
correctly refused to start; no device transfer or new CPU/battery measurement
was performed. The locked Mac GUI was skipped. Direct LAN proof, representative
bidirectional transfers and the remaining safety gates are tracked in
P2P5-rest-rest-rest-rest-rest; P2P3 remains no-go.

## P2P5-rest-rest-rest-rest-rest read-only preflight (2026-11-06)
Run `python3 tool/p2p_measure.py preflight` before planning a P30 measurement.
It reports the production first-install timestamp, the expected timestamp,
whether the isolated package is installed, and the charge counter and power
state. It exits nonzero when either package gate fails; it does not install,
launch, or modify either app. The begin/end sampler still independently checks
the production timestamp before and after each sample.

On this run adb reported `.profiletest` installed but no production package,
including in `pm list packages -u`, and no first-install timestamp. Preflight
therefore refused measurement. Battery reported 20,000 µAh, AC connected, and
status 4 (not charging); this snapshot is not consumption evidence. No app was
installed or launched, and the locked Mac GUI was skipped. Direct LAN proof,
bidirectional representative transfers, retries/resume, and meaningful CPU and
battery deltas remain in P2P5-rest-rest-rest-rest-rest-rest. P2P3 remains no-go.


## P2P5-rest-rest-rest-rest-rest-rest package-state diagnosis (2026-11-06)
The preflight now compares the active package list with the list including
uninstalled packages and reports the production package state as `installed`,
`uninstalled`, `missing`, or `inconsistent`. A timestamp with no active package,
or an active package absent from the inclusive list, is inconsistent and fails
the gate. The expected timestamp and isolated package remain mandatory. This
is read-only and does not repair or reinstall a package.

On the P30, the only listed Android user was the owner; the production package
was absent even from the inclusive list and its timestamp was unavailable.
The isolated package was present. Preflight refused measurements. Battery
reported 20,000 µAh, AC connected, status 4 (not charging); this is not a
consumption measurement. No app was installed or launched. The locked Mac GUI
was skipped. The production installation cannot be restored or its original
timestamp verified by this diagnostic; device transfers and the remaining
route, retry, resume, CPU and battery measurements are deferred to
P2P5-rest-rest-rest-rest-rest-rest-rest. P2P3 remains no-go.

## P2P5-rest-rest-rest-rest-rest-rest-rest reverse-direction runner (2026-11-06)
The existing isolated folder runner now supports either peer as sender. For
Android → Mac, start `python3 tool/p2p6/coordinator.py --sender android`,
build both runner entry points with `--dart-define=P2P_SENDER=android`, and
give the Android build `--dart-define=P2P_SOURCE=<absolute-scratch-folder>`.
The source must be a disposable folder accessible to the isolated app, not a
real vault. Forward port 47993 using `adb reverse`, launch the sender first,
wait for `ticket ready`, then launch the receiver. The receiver writes to
`p2p6-received` in its app support directory and reuses matching files; it
does not delete extra files. Use an empty destination for a clean measurement.
The default remains Mac → Android; both peers and the coordinator must agree
on the sender. A disconnected receiver can reconnect to the same ticket.
This is a development runner configured at build time, not a folder picker or
production sync. The coordinator test exercises both ticket forwarding and a
receiver disconnect, not the actual iroh transport.

The P30 preflight again reports the production package missing and no
first-install timestamp, so no app was installed or launched and no device
transfer was attempted. Battery reported 20,000 µAh, AC connected and status 4
(not charging). The locked Mac GUI was skipped. Route proof, representative
bidirectional measurements, retry/resume measurements and safety gates remain
in P2P5-rest-rest-rest-rest-rest-rest-rest-rest; P2P3 remains no-go.


## P2P5-rest-rest-rest-rest-rest-rest-rest-rest changed-file metric (2026-11-06)
Successful scratch folder receives now include `changed_files` in
`P2P6_TRANSFER_METRICS`: the number of manifest paths that differed from the
receiver's destination during the first comparison. This includes missing
files, counts paths rather than unique content hashes, and stays fixed across
retries; `blob_requests` still counts repeated requests. A zero count means the
manifest matched at that comparison. This does not count deletions or prove a
production reconciliation protocol.

P30 read-only preflight reported the production package missing, with no
first-install timestamp, while `.profiletest` was installed. Battery reported
20,000 µAh, AC connected and status 4 (not charging). No app was installed or
launched, no vault was written, and no transfer or energy measurement was
attempted. The locked Mac GUI was skipped. The unresolved device, route,
representative transfer and safety gates are tracked in
P2P5-rest-rest-rest-rest-rest-rest-rest-rest-rest; P2P3 remains no-go.
