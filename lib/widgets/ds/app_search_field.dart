import 'package:material_ui/material_ui.dart';

import '../app_icons.dart';
import '../constants.dart';

/// The one search field: outlined, dense, a search icon in front and a clear
/// button once there is text.
///
/// Use it for every field that filters a list: Library tabs (through
/// [LibraryToolbar]), the Search tab, Settings, and searches inside sheets. It
/// adds no padding of its own; inside an [AppSheet] it lines up with the title.
///
/// Pass [controller] when the caller sets or reads the text; otherwise the
/// field keeps its own. [fieldKey] keys the inner [TextField] for tests.
class AppSearchField extends StatefulWidget {
  const AppSearchField({
    super.key,
    required this.hintText,
    required this.onChanged,
    this.controller,
    this.fieldKey,
    this.autofocus = false,
  });

  final String hintText;
  final ValueChanged<String> onChanged;
  final TextEditingController? controller;
  final Key? fieldKey;
  final bool autofocus;

  @override
  State<AppSearchField> createState() => _AppSearchFieldState();
}

class _AppSearchFieldState extends State<AppSearchField> {
  TextEditingController? _own;

  TextEditingController get _controller =>
      widget.controller ?? (_own ??= TextEditingController());

  @override
  void dispose() {
    _own?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<TextEditingValue>(
        valueListenable: _controller,
        builder: (context, value, _) => TextField(
          key: widget.fieldKey,
          controller: _controller,
          autofocus: widget.autofocus,
          onChanged: widget.onChanged,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            isDense: true,
            hintText: widget.hintText,
            prefixIcon: const Icon(Icons.search, size: kIconSmall),
            border: const OutlineInputBorder(
              borderRadius: BorderRadius.all(Radius.circular(kRadiusMedium)),
            ),
            suffixIcon: value.text.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Clear search',
                    icon: const Icon(AppIcons.close, size: kIconSmall),
                    onPressed: () {
                      _controller.clear();
                      widget.onChanged('');
                    },
                  ),
          ),
        ),
      );
}
