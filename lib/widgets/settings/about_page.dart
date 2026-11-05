import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:typst_flutter/typst_flutter.dart' as p2p;
import 'package:path_provider/path_provider.dart';
import 'p2p_snapshot.dart';
import '../app_version.dart';
import '../ds/app_tile.dart';
import '../settings_sheet.dart';
import 'p2p_scratch_page.dart';
import 'settings_page.dart';

class AboutPage extends StatefulWidget {
  const AboutPage({super.key, required this.settings});
  final SettingsSheet settings;
  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  int taps = 0;
  bool developer = false;
  static const enabled = bool.fromEnvironment('P2P_HARNESS');

  Future<void> unlock() async {
    if (!enabled || kReleaseMode || ++taps < 7) return;
    if (Platform.isAndroid &&
        !(await const MethodChannel(
              'org.tylog.tylog/share',
            ).invokeMethod<bool>('isProfileTest') ??
            false)) {
      return;
    }
    if (mounted) setState(() => developer = true);
  }

  Future<void> openP2p() async {
    await p2p.initP2pHarness();
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => P2pScratchPage(
          start: (text) => p2p.startP2pScratch(text),
          startSnapshot: () async => p2p.startP2pScratch(
            await createRepresentativeScratchSnapshot(
              await getTemporaryDirectory(),
            ),
          ),
          receiveSnapshot: (ticket) async {
            final transfer = await p2p.receiveP2pScratch(ticket);
            final root = await getApplicationSupportDirectory();
            final directory = await restoreScratchSnapshot(transfer.text, root);
            final rate = transfer.elapsedMs == BigInt.zero
                ? 'n/a'
                : '${(transfer.bytes.toDouble() * 1000 / transfer.elapsedMs.toDouble() / 1024).toStringAsFixed(1)} KiB/s';
            return 'Restored synthetic folder to ${directory.path}\n${transfer.bytes} bytes in ${transfer.elapsedMs} ms ($rate; includes connection setup)';
          },
          receive: (ticket) async {
            final result = await p2p.receiveP2pScratch(ticket);
            return '${result.text}\n\n${result.bytes} bytes in ${result.elapsedMs} ms';
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => SettingsPage(
    title: 'About',
    children: [
      FutureBuilder<String>(
        future: appVersion(),
        builder: (_, snapshot) => ListTile(
          title: const Text('App version'),
          subtitle: Text(snapshot.data ?? '...'),
          onTap: enabled && !kReleaseMode ? unlock : null,
        ),
      ),
      if (developer)
        SwitchListTile(
          title: const Text('Developer: P2P scratch experiment'),
          value: developer,
          onChanged: (value) {
            if (value) {
              openP2p();
            } else {
              setState(() => developer = false);
              taps = 0;
            }
          },
          secondary: IconButton(
            icon: const Icon(Icons.open_in_new),
            onPressed: openP2p,
          ),
        ),
      if (widget.settings.onCheckForUpdates case final onTap?)
        AppTile(
          icon: Icons.system_update,
          title: 'Check for updates',
          subtitle: 'Download the latest release from GitHub',
          onTap: onTap,
        ),
      AppTile(
        icon: Icons.help_outline,
        title: 'Typst help',
        onTap: widget.settings.onTypstHelp,
      ),
    ],
  );
}
