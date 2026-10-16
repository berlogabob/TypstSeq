import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../vault_storage.dart';
import 'ds/app_tile.dart';

class BackgroundSyncNotice extends StatefulWidget {
  const BackgroundSyncNotice({super.key});

  @override
  State<BackgroundSyncNotice> createState() => _BackgroundSyncNoticeState();
}

class _BackgroundSyncNoticeState extends State<BackgroundSyncNotice>
    with WidgetsBindingObserver {
  bool? _ignoring;
  String _manufacturer = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _check();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _check();
  }

  Future<void> _check() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      final ignoring = await AndroidTreeVaultStorage.channel.invokeMethod<bool>(
        'isIgnoringBatteryOptimizations',
      );
      final manufacturer = await AndroidTreeVaultStorage.channel
          .invokeMethod<String>('deviceManufacturer');
      if (!mounted) return;
      setState(() {
        _ignoring = ignoring;
        _manufacturer = (manufacturer ?? '').toLowerCase();
      });
    } on PlatformException {
      // An unavailable status must not claim battery restrictions are enabled.
    } on MissingPluginException {
      // The bridge is unavailable in some test hosts.
    }
  }

  Future<void> _openSettings() async {
    try {
      await AndroidTreeVaultStorage.channel.invokeMethod<void>(
        'openBatterySettings',
      );
    } on PlatformException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.message ?? 'Battery settings are unavailable'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb ||
        defaultTargetPlatform != TargetPlatform.android ||
        _ignoring != false) {
      return const SizedBox.shrink();
    }
    final huawei = _manufacturer == 'huawei' || _manufacturer == 'honor';
    // Button below the text: beside it, the title wrapped to one word per
    // line on a phone.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        AppTile(
          icon: Icons.battery_alert_outlined,
          title: 'Background sync may stop',
          subtitle: 'Allow TyLog to run in the background',
          onTap: _openSettings,
        ),
        if (huawei)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SizedBox(
              width: double.infinity,
              child: Text(
                'Huawei: Settings > Battery > App launch > TyLog > '
                'Manage manually, enable all',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ),
        TextButton(
          onPressed: _openSettings,
          child: const Text('Battery settings'),
        ),
      ],
    );
  }
}
