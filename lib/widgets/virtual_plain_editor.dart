import 'dart:async';

import 'package:flutter/material.dart';

/// Plain-note editor that keeps only visible rows in the render tree.
///
/// The controllers are cheap model state; [ListView.builder] is the important
/// part: long notes no longer create one RenderEditable for the whole document.
class VirtualPlainEditor extends StatefulWidget {
  const VirtualPlainEditor({
    super.key,
    required this.source,
    required this.onChanged,
  });

  final String source;
  final ValueChanged<String> onChanged;

  @override
  State<VirtualPlainEditor> createState() => _VirtualPlainEditorState();
}

class _VirtualPlainEditorState extends State<VirtualPlainEditor> {
  final _scrollController = ScrollController();
  final _revision = ValueNotifier<int>(0);
  Timer? _emitTimer;
  bool _emitPending = false;
  final _undo = <String>[];
  final _redo = <String>[];
  late List<TextEditingController> _controllers;
  late String _source;

  @override
  void initState() {
    super.initState();
    _source = widget.source;
    _controllers = _makeControllers(_source);
  }

  List<TextEditingController> _makeControllers(String source) => [
    for (final line in source.split('\n')) TextEditingController(text: line),
  ];

  void _replaceControllers(String source) {
    final old = _controllers;
    _controllers = _makeControllers(source);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final controller in old) {
        controller.dispose();
      }
    });
  }

  @override
  void didUpdateWidget(VirtualPlainEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.source != _source) {
      _source = widget.source;
      _replaceControllers(_source);
      _undo.clear();
      _redo.clear();
      _revision.value++;
    }
  }

  String _readSource() =>
      _controllers.map((controller) => controller.text).join('\n');

  void _changed() {
    final undoWasEmpty = _undo.isEmpty;
    final redoWasNotEmpty = _redo.isNotEmpty;
    if (!_emitPending) {
      _undo.add(_source);
      if (_undo.length > 100) _undo.removeAt(0);
    }
    _redo.clear();
    _emitPending = true;
    _emitTimer?.cancel();
    _emitTimer = Timer(const Duration(milliseconds: 300), () {
      _emitPending = false;
      _source = _readSource();
      widget.onChanged(_source);
    });
    if (undoWasEmpty != _undo.isEmpty || redoWasNotEmpty != _redo.isNotEmpty) {
      _revision.value++;
    }
  }

  void _restore(String source) {
    _source = source;
    _replaceControllers(source);
    _emitTimer?.cancel();
    _emitPending = false;
    widget.onChanged(source);
    _revision.value++;
  }

  void _undoEdit() {
    if (_undo.isEmpty) return;
    final current = _readSource();
    final previous = _undo.removeLast();
    _redo.add(current);
    _restore(previous);
  }

  void _redoEdit() {
    if (_redo.isEmpty) return;
    final current = _readSource();
    final next = _redo.removeLast();
    _undo.add(current);
    _restore(next);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _emitTimer?.cancel();
    if (_emitPending) widget.onChanged(_readSource());
    _revision.dispose();
    for (final controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      SizedBox(
        height: 48,
        child: ListenableBuilder(
          listenable: _revision,
          builder: (context, _) => Row(
            children: [
              IconButton(
                tooltip: 'Undo',
                onPressed: _undo.isEmpty ? null : _undoEdit,
                icon: const Icon(Icons.undo),
              ),
              IconButton(
                tooltip: 'Redo',
                onPressed: _redo.isEmpty ? null : _redoEdit,
                icon: const Icon(Icons.redo),
              ),
            ],
          ),
        ),
      ),
      Expanded(
        child: ListView.builder(
          controller: _scrollController,
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.manual,
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
          itemCount: _controllers.length,
          itemBuilder: (context, index) => TextField(
            controller: _controllers[index],
            maxLines: null,
            minLines: 1,
            textAlignVertical: TextAlignVertical.top,
            style: Theme.of(
              context,
            ).textTheme.bodyLarge?.copyWith(height: 1.55),
            decoration: const InputDecoration(
              border: InputBorder.none,
              contentPadding: EdgeInsets.symmetric(vertical: 6),
            ),
            onChanged: (_) => _changed(),
          ),
        ),
      ),
    ],
  );
}
