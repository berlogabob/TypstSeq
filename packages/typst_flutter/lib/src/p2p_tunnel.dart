/// The native peer-to-peer tunnel (iroh), one node per app run.
///
/// Each device serves its vault as WebDAV on 127.0.0.1; this node carries
/// TCP connections to and from paired peers byte for byte (ALPN
/// `tylog/dav/1`) and pairs devices (ALPN `tylog/pair/1`).
///
/// ```dart
/// // On Android, first call the app's `org.tylog.tylog/share` method
/// // `initP2p` (iroh needs the Android context for DNS).
/// Future<String> p2pStart(Uint8List secretKey, int localDavPort,
///     String deviceName)          // → this node's id; again = update port/name
/// Future<void> p2pStop()
/// String? p2pNodeId()
/// void p2pSetPairedPeers(List<String> nodeIds) // allowlist for incoming
/// Future<int> p2pOpenPeerPort(String peerId)   // 127.0.0.1 port → peer's DAV
/// Future<void> p2pClosePeerPort(String peerId)
/// Future<String> p2pPeerRoute(String peerId)   // 'direct' | 'relay' | 'offline'
/// Future<String> p2pPairingCode()              // "TYLOG1…", 10 min, single use
/// Future<PairedPeer> p2pPair(String code)      // → PairedPeer(nodeId, name)
/// Stream<PairedPeer> p2pPairedEvents()         // peers that used our code
/// ```
///
/// Failures throw [PeerError] (`kind`: pairingRefused, unreachable, timeout,
/// notRunning, notEnabled, failed; plus `message`). A connection through a
/// peer port fails (reset or EOF) when the peer is offline or has not paired
/// this device. `p2pPeerRoute` dials the peer if no connection is open.
/// `p2pPairedEvents` needs a running node; only its latest listener hears.
library;

import 'dart:typed_data';

import 'rust/api/p2p_tunnel.dart' as api;
import 'rust/frb_generated.dart';

export 'rust/api/p2p_tunnel.dart' show PairedPeer, PeerError, PeerErrorKind;

Future<void> _init() async {
  try {
    await RustLib.init();
  } on StateError catch (error) {
    if (!error.message.contains('twice')) rethrow;
  }
}

Future<String> p2pStart(
  Uint8List secretKey,
  int localDavPort,
  String deviceName,
) async {
  await _init();
  return api.startNode(
    secretKey: secretKey,
    localDavPort: localDavPort,
    deviceName: deviceName,
  );
}

Future<void> p2pStop() => api.stopNode();

String? p2pNodeId() => api.nodeId();

void p2pSetPairedPeers(List<String> nodeIds) =>
    api.setPairedPeers(ids: nodeIds);

Future<int> p2pOpenPeerPort(String peerId) => api.openPeerPort(peer: peerId);

Future<void> p2pClosePeerPort(String peerId) => api.closePeerPort(peer: peerId);

Future<String> p2pPeerRoute(String peerId) => api.peerRoute(peer: peerId);

Future<String> p2pPairingCode() => api.pairingCode();

Future<api.PairedPeer> p2pPair(String code) => api.pair(code: code);

Stream<api.PairedPeer> p2pPairedEvents() => api.pairedEvents();
