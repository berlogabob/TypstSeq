part of '../app_mobile.dart';

/// P2P sync for the open vault. The node runs only while the vault has
/// paired devices or the Devices page is pairing one: an idle iroh endpoint
/// still costs network and battery.
extension _P2pFlow on _HomeScreenState {
  Future<void> _startP2p({bool force = false}) async {
    final registry = vaultRegistry;
    final opened = workspace.vault;
    if (registry == null || opened == null) return;
    final entry = registry.active;
    final current = _p2p;
    if (current != null &&
        current.vaultId == entry.id &&
        identical(current.vault, opened)) {
      if (!current.running) await current.start();
      return;
    }
    await _stopP2p();
    if (!force && entry.peers.isEmpty) return;
    late final P2pService service;
    service = P2pService(
      vaultId: entry.id,
      vault: opened,
      peers: () => registry.entries
          .firstWhere((item) => item.id == entry.id, orElse: () => entry)
          .peers,
      savePeers: (peers) => registry.setPeers(entry.id, peers),
      syncPeer: (config) =>
          workspace.syncNow(trigger: 'peer', configOverride: config),
      onPeerWrote: (_) => _queueP2pRescan(),
      onPeerAsked: (id) => unawaited(service.syncWith(id)),
    );
    _p2p = service;
    await service.start();
    _p2pTimer?.cancel();
    _p2pTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      if (_p2p == service && service.running) unawaited(service.syncAll());
    });
    unawaited(service.syncAll());
  }

  /// A peer's writes arrive in bursts; one rescan after they settle.
  void _queueP2pRescan() {
    _p2pRescanTimer?.cancel();
    _p2pRescanTimer = Timer(
      const Duration(seconds: 2),
      () =>
          unawaited(workspace.refreshIndex(updateStatus: false, always: true)),
    );
  }

  Future<void> _stopP2p() async {
    _p2pRescanTimer?.cancel();
    _p2pTimer?.cancel();
    _p2pTimer = null;
    final service = _p2p;
    _p2p = null;
    if (service != null) {
      await service.stop();
      service.dispose();
    }
  }

  Future<void> _showDevices() async {
    await _startP2p(force: true);
    final service = _p2p;
    if (!mounted || service == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            DevicesPage(service: service, peerErrors: workspace.peerSyncErrors),
      ),
    );
    // Pairing opened the node; keep it only if a device is now paired.
    if (_p2p == service && (vaultRegistry?.active.peers.isEmpty ?? true)) {
      await _stopP2p();
    }
  }
}
