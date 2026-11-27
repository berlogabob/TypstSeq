import 'package:material_ui/material_ui.dart';

import '../constants.dart';

/// Opens a modal bottom sheet. The only place the app calls
/// [showModalBottomSheet], so every sheet shares one drag handle and frame.
///
/// [builder] returns an [AppSheet] (or a widget built on one, such as a
/// picker). Set [isScrollControlled] when the sheet holds a text field or
/// needs more than half the screen.
///
/// [bare] is for the rare sheet that paints its own surface (the draggable
/// Incoming sheet): it makes the route transparent and inset by the safe area,
/// and the builder is then responsible for the handle and title itself.
Future<T?> showAppSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  bool isScrollControlled = false,
  bool isDismissible = true,
  bool enableDrag = true,
  BoxConstraints? constraints,
  bool bare = false,
}) => showModalBottomSheet<T>(
  context: context,
  // AppSheet draws the handle, so the Material one would be a second handle.
  showDragHandle: false,
  isScrollControlled: isScrollControlled,
  isDismissible: isDismissible,
  enableDrag: enableDrag,
  constraints: constraints,
  useSafeArea: bare,
  backgroundColor: bare ? Colors.transparent : null,
  builder: builder,
);

/// The one frame for bottom sheets: drag handle, `titleLarge` title, safe
/// area and [kSpace16] gutters. Open it with [showAppSheet].
///
/// The default constructor scrolls its [children] when they outgrow the sheet.
/// [AppSheet.body] takes a single child that manages its own scrolling or
/// flex (a search field above a list, for example).
class AppSheet extends StatelessWidget {
  const AppSheet({
    super.key,
    required this.title,
    required this.children,
    this.subtitle,
    this.trailing,
  }) : body = null;

  /// Keeps a scrolling or flex-based body bounded by the sheet height.
  const AppSheet.body({
    super.key,
    required this.title,
    required Widget child,
    this.subtitle,
    this.trailing,
  }) : body = child,
       children = const [];

  final String title;

  /// One or two lines of context under the title, such as the text a choice
  /// refers to.
  final String? subtitle;

  /// An action on the title row, such as Skip.
  final Widget? trailing;
  final List<Widget> children;
  final Widget? body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final heading = Semantics(
      header: true,
      child: Text(title, style: theme.textTheme.titleLarge),
    );
    final content = [
      Center(
        child: Container(
          width: kMinTapTarget,
          height: kSpace4,
          margin: const EdgeInsets.only(bottom: kSpace16),
          decoration: BoxDecoration(
            color: theme.colorScheme.onSurfaceVariant,
            borderRadius: BorderRadius.circular(kRadiusSmall),
          ),
        ),
      ),
      if (trailing == null)
        heading
      else
        Row(
          children: [
            Expanded(child: heading),
            trailing!,
          ],
        ),
      if (subtitle != null) ...[
        const SizedBox(height: kSpace4),
        Text(
          subtitle!,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
      const SizedBox(height: kSpace12),
    ];
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          kSpace16,
          kSpace8,
          kSpace16,
          kSpace24,
        ),
        // The sheet already supplies the 16dp gutter, so rows inside it take
        // no inset of their own: their text lines up with the title.
        child: ListTileTheme.merge(
          contentPadding: EdgeInsets.zero,
          child: _content(content),
        ),
      ),
    );
  }

  Widget _content(List<Widget> content) => body != null
      ? Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ...content,
            Flexible(child: body!),
          ],
        )
      : SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [...content, ...children],
          ),
        );
}
