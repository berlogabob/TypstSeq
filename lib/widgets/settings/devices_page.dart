import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:typst_flutter/typst_flutter.dart' show PeerError;

import '../../p2p/p2p_service.dart';
import '../../p2p/peer_entry.dart';
import '../app_icons.dart';
import '../constants.dart';
import '../ds/app_sheet.dart';
import '../ds/app_tile.dart';
import '../snack.dart';
import 'scope_note.dart';
import 'settings_page.dart';

/// Pair devices for P2P sync and see each one's state.
class DevicesPage extends StatefulWidget {
  const DevicesPage({
    super.key,
    required this.service,
    this.peerErrors = const {},
  });

  final P2pService service;

  /// Last sync failure per peer node id (from the workspace).
  final Map<String, String> peerErrors;

  @override
  State<DevicesPage> createState() => _DevicesPageState();
}

class _DevicesPageState extends State<DevicesPage> {
  final _code = TextEditingController();
  String? _shownCode;
  bool _busy = false;

  P2pService get service => widget.service;

  @override
  void initState() {
    super.initState();
    service.addListener(_changed);
  }

  @override
  void dispose() {
    service.removeListener(_changed);
    _code.dispose();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } on PeerError catch (error) {
      if (mounted) showSnack(context, error.message);
    } catch (error) {
      if (mounted) showSnack(context, '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _showCode() => _run(() async {
    final code = await service.pairingCode();
    setState(() => _shownCode = code);
  });

  Future<void> _pair() => _run(() async {
    final peer = await service.pair(_code.text);
    _code.clear();
    if (mounted) showSnack(context, 'Paired with ${peer.name}');
    unawaited(service.syncAll());
  });

  String _subtitle(PeerEntry peer) {
    final error = widget.peerErrors[peer.nodeId];
    if (error != null) return 'Last try failed: $error';
    final last = peer.lastSyncAt;
    if (last == null) return 'Not synced yet';
    final route = peer.lastRoute == 'relay' ? ' · via relay' : '';
    return 'Synced ${_ago(last)}$route';
  }

  static String _ago(DateTime at) {
    final elapsed = DateTime.now().toUtc().difference(at.toUtc());
    if (elapsed.inMinutes < 1) return 'just now';
    if (elapsed.inHours < 1) return '${elapsed.inMinutes} min ago';
    if (elapsed.inDays < 1) return '${elapsed.inHours} h ago';
    return '${elapsed.inDays} d ago';
  }

  Future<void> _peerMenu(PeerEntry peer) async {
    final action = await showAppSheet<String>(
      context,
      builder: (context) => AppSheet(
        title: peer.name,
        children: [
          ListTile(
            leading: const Icon(AppIcons.sync),
            title: const Text('Sync now'),
            onTap: () => Navigator.pop(context, 'sync'),
          ),
          ListTile(
            leading: const Icon(AppIcons.delete),
            title: const Text('Remove device'),
            subtitle: const Text('It stops syncing with this vault'),
            onTap: () => Navigator.pop(context, 'remove'),
          ),
        ],
      ),
    );
    if (action == 'sync') {
      await _run(() async {
        final ok = await service.syncWith(peer.nodeId);
        if (mounted) {
          showSnack(context, ok ? 'Synced with ${peer.name}' : 'Sync failed');
        }
      });
    } else if (action == 'remove') {
      await _run(() => service.removePeer(peer.nodeId));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final peers = service.peers();
    final unavailable = service.unavailable;
    return SettingsPage(
      title: 'Devices',
      children: [
        Padding(
          padding: const EdgeInsets.all(kSpace8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Sync this vault directly with your other devices, without '
                'a server. Both devices must have TyLog open.',
                style: theme.textTheme.bodyMedium,
              ),
              const ScopeNote('This vault'),
              if (unavailable != null) ...[
                const SizedBox(height: kSpace8),
                Text(
                  unavailable,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ],
            ],
          ),
        ),
        for (final peer in peers)
          AppTile(
            icon: AppIcons.syncManaged,
            title: peer.name,
            subtitle: _subtitle(peer),
            onTap: _busy ? null : () => _peerMenu(peer),
          ),
        if (service.running) ...[
          const Divider(),
          Padding(
            padding: const EdgeInsets.all(kSpace8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Pair a device', style: theme.textTheme.titleMedium),
                const SizedBox(height: kSpace8),
                Text(
                  'On one device show a code; on the other enter it. '
                  'The code works once, for 10 minutes.',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: kSpace8),
                if (_shownCode != null) ...[
                  SelectableText(
                    _shownCode!,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontFamily: 'monospace',
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: _shownCode!));
                      if (context.mounted) showSnack(context, 'Code copied');
                    },
                    icon: const Icon(Icons.copy_outlined),
                    label: const Text('Copy code'),
                  ),
                ] else
                  OutlinedButton(
                    onPressed: _busy ? null : _showCode,
                    child: const Text('Show a code'),
                  ),
                const SizedBox(height: kSpace16),
                TextField(
                  controller: _code,
                  decoration: const InputDecoration(
                    labelText: 'Code from the other device',
                  ),
                  maxLines: 2,
                  minLines: 1,
                ),
                const SizedBox(height: kSpace8),
                FilledButton(
                  onPressed: _busy ? null : _pair,
                  child: const Text('Pair'),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
