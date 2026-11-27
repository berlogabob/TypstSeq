import 'package:material_ui/material_ui.dart';

import '../constants.dart';

/// The one row style for settings pages, the More drawer and other padded
/// containers: leading icon, title, optional subtitle and trailing widget.
///
/// Use it inside a container that already supplies the [kSpace16] page gutter
/// (an [AppSheet], a settings page). The tile adds [kSpace8] of its own so its
/// rounded highlight does not touch the text. For edge-to-edge lists (library
/// rows, search results) use a plain [ListTile], which takes the theme's
/// [kSpace16] inset and lines up with the same text column.
///
/// States: tappable when [onTap] is set, a plain info row when it is null,
/// dimmed and inert when [enabled] is false, tinted when [selected].
class AppTile extends StatelessWidget {
  const AppTile({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.enabled = true,
    this.selected = false,
    this.singleLineSubtitle = false,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;

  /// Null renders a read-only fact (App version, Local folder) with no ink.
  final VoidCallback? onTap;

  /// False dims the row and ignores taps, for actions that cannot run now.
  final bool enabled;

  /// Marks the current choice in a list of alternatives.
  final bool selected;

  /// Keeps long values such as paths on one ellipsised line.
  final bool singleLineSubtitle;

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: kSpace8),
    shape: const RoundedRectangleBorder(borderRadius: kRadiusListTile),
    enabled: enabled,
    selected: selected,
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
