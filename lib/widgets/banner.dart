import 'package:material_ui/material_ui.dart';

MaterialBanner appBanner({
  Key? key,
  required Widget content,
  required List<Widget> actions,
  required Color? backgroundColor,
  double? elevation,
}) => MaterialBanner(
  key: key,
  content: content,
  actions: actions,
  backgroundColor: backgroundColor,
  elevation: elevation,
);
