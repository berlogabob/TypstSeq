import 'package:flutter/material.dart';
import '../app_version.dart';
import '../ds/app_tile.dart';
import '../settings_sheet.dart';
import 'settings_page.dart';

class AboutPage extends StatelessWidget {
  const AboutPage({super.key, required this.settings});
  final SettingsSheet settings;
  @override
  Widget build(BuildContext context) => SettingsPage(
    title: 'About',
    children: [
      FutureBuilder<String>(
        future: appVersion(),
        builder: (_, snapshot) => ListTile(
          title: const Text('App version'),
          subtitle: Text(snapshot.data ?? '...'),
        ),
      ),
      if (settings.onCheckForUpdates case final onTap?)
        AppTile(
          icon: Icons.system_update,
          title: 'Check for updates',
          subtitle: 'Download the latest release from GitHub',
          onTap: onTap,
        ),
      AppTile(
        icon: Icons.help_outline,
        title: 'Typst help',
        onTap: settings.onTypstHelp,
      ),
    ],
  );
}
