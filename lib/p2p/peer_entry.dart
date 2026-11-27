/// A device paired with one vault for P2P sync, stored on its `VaultEntry` in
/// `vaults.json`. The shared DAV password lives in the OS keystore, never here
/// (as with the Nextcloud password).
class PeerEntry {
  const PeerEntry({
    required this.nodeId,
    required this.name,
    required this.pairedAt,
    this.lastSyncAt,
    this.lastRoute,
  });

  /// The peer's iroh node id: its identity in the tunnel allowlist, and the
  /// key of its sync cursors (`.tylog/sync_state.peer-<id>.json`).
  final String nodeId;
  final String name;
  final DateTime pairedAt;
  final DateTime? lastSyncAt;

  /// 'direct' or 'relay' at the last successful sync.
  final String? lastRoute;

  PeerEntry copyWith({String? name, DateTime? lastSyncAt, String? lastRoute}) =>
      PeerEntry(
        nodeId: nodeId,
        name: name ?? this.name,
        pairedAt: pairedAt,
        lastSyncAt: lastSyncAt ?? this.lastSyncAt,
        lastRoute: lastRoute ?? this.lastRoute,
      );

  Map<String, Object?> toJson() => {
    'nodeId': nodeId,
    'name': name,
    'pairedAt': pairedAt.toUtc().toIso8601String(),
    if (lastSyncAt != null) 'lastSyncAt': lastSyncAt!.toUtc().toIso8601String(),
    if (lastRoute != null) 'lastRoute': lastRoute,
  };

  /// Null for an entry missing its node id (a hand-edited or damaged file):
  /// dropping it un-pairs that device rather than failing the whole registry.
  static PeerEntry? fromJson(Object? json) {
    if (json is! Map) return null;
    final nodeId = json['nodeId'];
    if (nodeId is! String || nodeId.isEmpty) return null;
    return PeerEntry(
      nodeId: nodeId,
      name: json['name'] as String? ?? 'Device',
      pairedAt:
          DateTime.tryParse(json['pairedAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      lastSyncAt: DateTime.tryParse(json['lastSyncAt'] as String? ?? ''),
      lastRoute: json['lastRoute'] as String?,
    );
  }
}
