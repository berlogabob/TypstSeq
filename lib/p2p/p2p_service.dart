import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:material_ui/material_ui.dart' show ChangeNotifier;
import 'package:typst_flutter/typst_flutter.dart' as native;

import '../nextcloud_sync.dart';
import '../vault.dart';
import 'peer_entry.dart';
import 'vault_dav_server.dart';

/// P2P sync for the open vault: serves it to paired devices through the iroh
/// tunnel and syncs with each of them through the ordinary engine.
///
/// For each pair one side syncs and the other only serves, so a pair keeps a
/// single set of cursors: the device with the smaller node id syncs. The other
/// pokes it (`POST /tylog-notify`) after a local write, so its edits still
/// travel within seconds.
///
/// Both sides derive the pair's DAV password from the pairing code they both
/// saw; it is kept in the OS keystore, per vault and peer.
class P2pService extends ChangeNotifier {
  P2pService({
    required this.vaultId,
    required this.vault,
    required this.peers,
    required this.savePeers,
    required this.syncPeer,
    this.onPeerWrote,
    this.onPeerAsked,
  });

  final String vaultId;
  final Vault vault;

  /// The vault's paired peers, read fresh each time (the registry owns them).
  final List<PeerEntry> Function() peers;
  final Future<void> Function(List<PeerEntry> peers) savePeers;

  /// Runs one sync of [vault] against a peer's config, through the workspace
  /// (`syncNow(configOverride: ...)`), so progress, conflicts and the index
  /// update exactly as for Nextcloud. True when it succeeded.
  final Future<bool> Function(NextcloudConfig config) syncPeer;

  /// A peer wrote [path] into this vault: rescan it.
  final void Function(String path)? onPeerWrote;

  /// A peer asked this device to sync with it now.
  final void Function(String peerId)? onPeerAsked;

  static const _secure = FlutterSecureStorage();
  static const _nodeKeyName = 'p2p-node-key';

  VaultDavServer? _server;
  String? _nodeId;
  String? _code;
  StreamSubscription<native.PairedPeer>? _pairedEvents;
  final _secrets = <String, String>{};
  final _openPorts = <String, int>{};

  /// Why P2P is off on this device (a build without the native feature), or
  /// null while it runs.
  String? unavailable;

  String? get nodeId => _nodeId;
  bool get running => _nodeId != null;

  Future<void> start() async {
    if (running) return;
    try {
      if (Platform.isAndroid) {
        final ready = await const MethodChannel(
          'org.tylog.tylog/share',
        ).invokeMethod<bool>('initP2p');
        if (ready != true) {
          unavailable = 'P2P is not included in this build';
          notifyListeners();
          return;
        }
      }
      for (final peer in peers()) {
        _secrets[peer.nodeId] =
            await _secure.read(key: _secretKey(peer.nodeId)) ?? '';
      }
      final server = VaultDavServer(
        storage: vault.storage,
        generation: vault.writeGeneration,
        authorize: (user, password) {
          final expected = _secrets[user];
          return expected != null &&
              expected.isNotEmpty &&
              constantTimeEquals(password, expected);
        },
        onWritten: (path) {
          vault.restoreWriteMarkers(path, stale: true, pendingSync: true);
          onPeerWrote?.call(path);
        },
        onNotify: () {
          // The tunnel hides which peer asked; sync every peer we lead.
          for (final peer in peers()) {
            if (_leads(peer.nodeId)) onPeerAsked?.call(peer.nodeId);
          }
        },
      );
      final port = await server.start();
      _server = server;
      _nodeId = await native.p2pStart(await _nodeKey(), port, _deviceName());
      native.p2pSetPairedPeers(peers().map((peer) => peer.nodeId).toList());
      _pairedEvents = native.p2pPairedEvents().listen(_paired);
      unavailable = null;
    } on native.PeerError catch (error) {
      await _server?.close();
      _server = null;
      _nodeId = null;
      unavailable = error.kind == native.PeerErrorKind.notEnabled
          ? 'P2P is not included in this build'
          : error.message;
    }
    notifyListeners();
  }

  Future<void> stop() async {
    await _pairedEvents?.cancel();
    _pairedEvents = null;
    for (final peer in _openPorts.keys.toList()) {
      await native.p2pClosePeerPort(peer);
    }
    _openPorts.clear();
    if (running) await native.p2pStop();
    _nodeId = null;
    await _server?.close();
    _server = null;
    notifyListeners();
  }

  /// A one-time code for another device to enter (10 minutes, single use).
  Future<String> pairingCode() async {
    final code = await native.p2pPairingCode();
    _code = code;
    return code;
  }

  /// Pairs with the device that showed [code].
  Future<PeerEntry> pair(String code) async {
    final peer = await native.p2pPair(code.trim());
    return _addPeer(peer.nodeId, peer.name, _secretFor(code.trim()));
  }

  Future<void> _paired(native.PairedPeer peer) async {
    final code = _code;
    if (code == null) return;
    _code = null;
    await _addPeer(peer.nodeId, peer.name, _secretFor(code));
  }

  Future<PeerEntry> _addPeer(String id, String name, String secret) async {
    await _secure.write(key: _secretKey(id), value: secret);
    _secrets[id] = secret;
    final entry = PeerEntry(
      nodeId: id,
      name: name,
      pairedAt: DateTime.now().toUtc(),
    );
    await savePeers([
      for (final peer in peers())
        if (peer.nodeId != id) peer,
      entry,
    ]);
    native.p2pSetPairedPeers(peers().map((peer) => peer.nodeId).toList());
    notifyListeners();
    return entry;
  }

  Future<void> removePeer(String id) async {
    await savePeers([
      for (final peer in peers())
        if (peer.nodeId != id) peer,
    ]);
    await _secure.delete(key: _secretKey(id));
    _secrets.remove(id);
    if (_openPorts.remove(id) != null) await native.p2pClosePeerPort(id);
    if (running) {
      native.p2pSetPairedPeers(peers().map((peer) => peer.nodeId).toList());
    }
    notifyListeners();
  }

  /// One pass over every paired peer: sync those this device leads, poke the
  /// others when this device has writes they have not seen.
  Future<void> syncAll() async {
    if (!running) return;
    for (final peer in peers()) {
      try {
        if (_leads(peer.nodeId)) {
          await syncWith(peer.nodeId);
        } else if (vault.pendingSyncWritesFor(peer.nodeId).isNotEmpty) {
          final pending = vault.pendingSyncWritesFor(peer.nodeId);
          if (await _notify(peer.nodeId)) {
            vault.clearPendingSyncWrites(pending, remote: peer.nodeId);
          }
        }
      } on native.PeerError {
        // Offline or unreachable: the next pass tries again.
      }
    }
  }

  Future<bool> syncWith(String peerId) async {
    final ok = await syncPeer(await peerConfig(peerId));
    if (ok) {
      final route = await native.p2pPeerRoute(peerId);
      await savePeers([
        for (final peer in peers())
          peer.nodeId == peerId
              ? peer.copyWith(
                  lastSyncAt: DateTime.now().toUtc(),
                  lastRoute: route,
                )
              : peer,
      ]);
    }
    return ok;
  }

  Future<NextcloudConfig> peerConfig(String peerId) async {
    final port = _openPorts[peerId] ??= await native.p2pOpenPeerPort(peerId);
    return NextcloudConfig(
      serverUrl: 'http://127.0.0.1:$port${VaultDavServer.rootPath}',
      username: _nodeId!,
      password: _secrets[peerId] ?? '',
      kind: 'peer',
      peerId: peerId,
    );
  }

  Future<bool> _notify(String peerId) async {
    final config = await peerConfig(peerId);
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    try {
      final request = await client.postUrl(
        Uri.parse(config.serverUrl).replace(path: '/tylog-notify'),
      );
      request.headers.set(
        HttpHeaders.authorizationHeader,
        'Basic ${base64Encode(utf8.encode('${config.username}:${config.password}'))}',
      );
      final response = await request.close().timeout(
        const Duration(seconds: 20),
      );
      await response.drain<void>();
      return response.statusCode == HttpStatus.noContent;
    } on IOException {
      return false;
    } on TimeoutException {
      return false;
    } finally {
      client.close(force: true);
    }
  }

  bool _leads(String peerId) => (_nodeId ?? '').compareTo(peerId) < 0;

  String _secretKey(String peerId) => 'p2p-dav-$vaultId-$peerId';

  static String _secretFor(String code) =>
      sha256.convert(utf8.encode('tylog-dav:$code')).toString();

  static String _deviceName() {
    try {
      return Platform.localHostname;
    } catch (_) {
      return Platform.operatingSystem;
    }
  }

  static Future<Uint8List> _nodeKey() async {
    final stored = await _secure.read(key: _nodeKeyName);
    if (stored != null) {
      final bytes = base64Decode(stored);
      if (bytes.length == 32) return bytes;
    }
    final random = Random.secure();
    final key = Uint8List.fromList(
      List.generate(32, (_) => random.nextInt(256)),
    );
    await _secure.write(key: _nodeKeyName, value: base64Encode(key));
    return key;
  }

  @override
  void dispose() {
    unawaited(stop());
    super.dispose();
  }
}
