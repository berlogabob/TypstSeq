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
