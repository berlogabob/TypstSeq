import 'package:flutter/material.dart';

import '../constants.dart';

class AppTile extends StatelessWidget {
  const AppTile({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.singleLineSubtitle = false,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool singleLineSubtitle;

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: kSpace8),
    shape: const RoundedRectangleBorder(borderRadius: listTileRadius),
    leading: Icon(icon, size: kIcon),
    title: Text(title),
    subtitle: subtitle == null
        ? null
        : Text(
            subtitle!,
            softWrap: !singleLineSubtitle,
            maxLines: singleLineSubtitle ? 1 : 2,
            overflow: TextOverflow.ellipsis,
          ),
    trailing: trailing,
    onTap: onTap,
  );
}
