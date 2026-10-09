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

  void _statusMenu(BuildContext context, Offset position) =>
      _field(context, 'status', position & const Size(1, 1));

  void _field(BuildContext context, String field, Rect anchor) {
    if (field == 'status' ? onSetStatus == null : onSetField == null) return;
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    var bounds = Offset.zero & overlay.size;
    final body = Scaffold.maybeOf(context)?.widget.body;
    context.visitAncestorElements((element) {
      if (element.widget != body) return true;
      final box = element.findRenderObject()! as RenderBox;
      bounds = box.localToGlobal(Offset.zero, ancestor: overlay) & box.size;
      return false;
    });
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
          TaskFieldPopup(
            field: field,
            anchor: anchor,
            bounds: bounds,
            onPicked: (value) {
              _menu.remove();
              unawaited(
                field == 'status'
                    ? onSetStatus!(task, value)
                    : onSetField!(task, field, value),
              );
            },
          ),
        ],
      ),
    );
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
              _field(context, field, box.localToGlobal(Offset.zero) & box.size);
            },
          ),
        ),
      ],
    ),
    onTap: () => widget.onOpenPath(task.notePath),
  );
}
