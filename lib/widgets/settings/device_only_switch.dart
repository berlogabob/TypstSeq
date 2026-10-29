import 'package:flutter/material.dart';
import 'package:tylog_core/storage.dart';

import '../../settings_path.dart';

class DeviceOnlySwitch extends StatefulWidget {
  const DeviceOnlySwitch({
    super.key,
    required this.storage,
    required this.sharedPath,
  });

  final VaultStorage storage;
  final String sharedPath;

  @override
  State<DeviceOnlySwitch> createState() => _DeviceOnlySwitchState();
}

class _DeviceOnlySwitchState extends State<DeviceOnlySwitch> {
  bool? _enabled;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(DeviceOnlySwitch oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.storage != widget.storage ||
        oldWidget.sharedPath != widget.sharedPath) {
      _enabled = null;
      _load();
    }
  }

  Future<void> _load() async {
    final path = await settingsPathFor(widget.storage, widget.sharedPath);
    if (mounted) setState(() => _enabled = path != widget.sharedPath);
  }

  Future<void> _change(bool enabled) async {
    setState(() => _busy = true);
    try {
      await setSettingsDeviceOnly(widget.storage, widget.sharedPath, enabled);
      if (mounted) setState(() => _enabled = enabled);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not change settings scope: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => SwitchListTile(
    title: const Text('This device only'),
    subtitle: const Text('Off: shared across your devices through the vault'),
    value: _enabled ?? false,
    onChanged: _enabled == null || _busy ? null : _change,
  );
}
