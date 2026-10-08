import 'dart:async';
import 'package:flutter/material.dart';
import '../models.dart';
import 'task_checkbox.dart';
import 'task_chip_strip.dart';
import 'task_fields.dart';

class TaskRow extends StatefulWidget {
  const TaskRow({
    super.key,
    required this.task,
    required this.onOpenPath,
    this.onSetStatus,
    this.onSetField,
    this.subtitle,
  });
  final TaskRef task;
  final ValueChanged<String> onOpenPath;
  final Future<void> Function(TaskRef, String)? onSetStatus;
  final Future<void> Function(TaskRef, String, String)? onSetField;
  final String? subtitle;

  @override
  State<TaskRow> createState() => _TaskRowState();
}

class _TaskRowState extends State<TaskRow> {
  final _menu = ContextMenuController();
  TaskRef get task => widget.task;
  Future<void> Function(TaskRef, String)? get onSetStatus => widget.onSetStatus;
  Future<void> Function(TaskRef, String, String)? get onSetField =>
      widget.onSetField;
  @override
  void dispose() {
    _menu.remove();
    super.dispose();
  }

  void _statusMenu(BuildContext context, Offset position) {
    _menu.show(
      context: context,
      contextMenuBuilder: (context) => Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              onTap: _menu.remove,
              behavior: HitTestBehavior.opaque,
            ),
          ),
          TaskStatusMenu(
            anchors: TextSelectionToolbarAnchors(primaryAnchor: position),
            onStatus: (status) {
              _menu.remove();
              unawaited(onSetStatus?.call(task, status));
            },
          ),
        ],
      ),
    );
  }

  Future<void> _field(
    BuildContext context,
    String field,
    Offset position,
  ) async {
    if (onSetField == null) return;
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final value = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        position & const Size(1, 1),
        Offset.zero & overlay.size,
      ),
      items: [
        PopupMenuItem(
          enabled: false,
          child: SizedBox(
            width: 280,
            height: 260,
            child: TaskFieldPopup(field: field),
          ),
        ),
      ],
    );
    if (mounted && value != null) await onSetField!(task, field, value);
  }

  @override
  Widget build(BuildContext context) => ListTile(
    leading: Tooltip(
      message: 'Task status',
      triggerMode: TooltipTriggerMode.manual,
      child: GestureDetector(
        onLongPressStart: onSetStatus == null
            ? null
            : (details) => _statusMenu(context, details.globalPosition),
        child: IconButton(
          onPressed: onSetStatus == null
              ? null
              : () => unawaited(
                  onSetStatus!(task, task.status == 'done' ? 'todo' : 'done'),
                ),
          icon: Text(switch (task.status) {
            'doing' => taskDoingGlyph,
            'done' => taskCheckedGlyph,
            'cancelled' => taskCancelledGlyph,
            _ => taskUncheckedGlyph,
          }, style: Theme.of(context).textTheme.titleLarge),
        ),
      ),
    ),
    title: Text(
      task.text,
      style: task.status == 'cancelled' || task.status == 'done'
          ? const TextStyle(decoration: TextDecoration.lineThrough)
          : null,
    ),
    subtitle: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.subtitle != null && widget.subtitle!.isNotEmpty)
          Text(widget.subtitle!),
        Builder(
          builder: (context) => TaskChipStrip(
            task: task,
            showEmpty: onSetField != null,
            onCommand: (field) {
              final box = context.findRenderObject()! as RenderBox;
              unawaited(_field(context, field, box.localToGlobal(Offset.zero)));
            },
          ),
        ),
      ],
    ),
    onTap: () => widget.onOpenPath(task.notePath),
  );
}

class TaskQuickAdd extends StatefulWidget {
  const TaskQuickAdd({super.key, required this.onAdd});
  final Future<void> Function(String) onAdd;
  @override
  State<TaskQuickAdd> createState() => _TaskQuickAddState();
}

class _TaskQuickAddState extends State<TaskQuickAdd> {
  final _input = TextEditingController();
  bool _saving = false;
  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(
    key: const Key('task-quick-add'),
    controller: _input,
    maxLines: 1,
    enabled: !_saving,
    decoration: const InputDecoration(hintText: 'Add task…'),
    onSubmitted: (value) async {
      final text = value.trim();
      if (text.isEmpty || _saving) return;
      setState(() => _saving = true);
      try {
        await widget.onAdd(text);
        if (mounted) _input.clear();
      } catch (_) {
        // The app reports persistence errors; keep the text for retry.
      } finally {
        if (mounted) setState(() => _saving = false);
      }
    },
  );
}
