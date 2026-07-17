import 'package:flutter/material.dart';

class Editor extends StatefulWidget {
  const Editor({
    super.key,
    required this.controller,
    required this.onChanged,
    this.monospace = false,
  });

  final TextEditingController controller;
  final VoidCallback onChanged;
  final bool monospace;

  @override
  State<Editor> createState() => EditorState();
}

class EditorState extends State<Editor> {
  final focusNode = FocusNode();

  void requestFocus() => focusNode.requestFocus();

  @override
  void dispose() {
    focusNode.dispose();
    super.dispose();
  }

  void _replace(String before, String after) {
    final controller = widget.controller;
    final selection = controller.selection;
    final start = selection.isValid ? selection.start : controller.text.length;
    final end = selection.isValid ? selection.end : controller.text.length;
    final selected = controller.text.substring(start, end);
    controller.value = controller.value.copyWith(
      text: controller.text.replaceRange(start, end, '$before$selected$after'),
      selection: TextSelection.collapsed(
        offset: start + before.length + selected.length,
      ),
      composing: TextRange.empty,
    );
    widget.onChanged();
    focusNode.requestFocus();
  }

  void _linePrefix(String prefix) {
    final controller = widget.controller;
    final selection = controller.selection;
    final cursor = selection.isValid ? selection.start : controller.text.length;
    final lineStart = cursor == 0
        ? 0
        : controller.text.lastIndexOf('\n', cursor - 1) + 1;
    controller.value = controller.value.copyWith(
      text: controller.text.replaceRange(lineStart, lineStart, prefix),
      selection: TextSelection.collapsed(offset: cursor + prefix.length),
      composing: TextRange.empty,
    );
    widget.onChanged();
    focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Expanded(
        child: TextField(
          controller: widget.controller,
          focusNode: focusNode,
          expands: true,
          maxLines: null,
          minLines: null,
          textAlignVertical: TextAlignVertical.top,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
            height: 1.45,
            fontFamily: widget.monospace ? 'monospace' : null,
          ),
          decoration: const InputDecoration(contentPadding: EdgeInsets.all(18)),
          onChanged: (_) => widget.onChanged(),
        ),
      ),
      ListenableBuilder(
        listenable: focusNode,
        builder: (context, _) => focusNode.hasFocus
            ? SafeArea(
                top: false,
                child: SizedBox(
                  height: 48,
                  child: ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    scrollDirection: Axis.horizontal,
                    children: [
                      _DockButton('=', 'Heading', () => _linePrefix('= ')),
                      _DockButton('*', 'Bold', () => _replace('*', '*')),
                      _DockButton('_', 'Emphasis', () => _replace('_', '_')),
                      _DockButton(r'$', 'Math', () => _replace(r'$', r'$')),
                      _DockButton(
                        '#',
                        'Function or tag',
                        () => _replace('#', ''),
                      ),
                      _DockButton('+', 'New block', () => _replace('\n- ', '')),
                    ],
                  ),
                ),
              )
            : const SizedBox.shrink(),
      ),
    ],
  );
}

class _DockButton extends StatelessWidget {
  const _DockButton(this.label, this.tooltip, this.onPressed);

  final String label;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 2),
    child: IconButton.outlined(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Text(label),
    ),
  );
}
