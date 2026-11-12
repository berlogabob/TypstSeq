import 'dart:async';
import 'package:material_ui/material_ui.dart';
import 'package:tylog_core/tylog_core.dart' show isOpenLoan;
import '../models.dart';
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
    this.compact = false,
  });
  final TaskRef task;
  final ValueChanged<String> onOpenPath;
  final Future<void> Function(TaskRef, String)? onSetStatus;
  final Future<void> Function(TaskRef, String, String)? onSetField;
  final String? subtitle;
  // Inside a page (journal read view): tight row, chips only for set fields.
  final bool compact;

  @override
  State<TaskRow> createState() => _TaskRowState();
}

class _TaskRowState extends State<TaskRow> {
  LocalHistoryEntry? _menuHistory;
  late final _menu = ContextMenuController(
    onRemove: () {
      final history = _menuHistory;
      _menuHistory = null;
      history?.remove();
    },
  );
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
    _menu.remove();
    _menuHistory = LocalHistoryEntry(onRemove: _menu.remove);
    ModalRoute.of(context)?.addLocalHistoryEntry(_menuHistory!);
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

  Widget _status(BuildContext context) => Tooltip(
    message: isOpenLoan(task) ? 'Returned' : 'Task status',
    triggerMode: TooltipTriggerMode.manual,
    child: GestureDetector(
      onLongPressStart: onSetStatus == null
          ? null
          : (details) => _statusMenu(context, details.globalPosition),
      child: IconButton(
        visualDensity: widget.compact ? VisualDensity.compact : null,
        onPressed: onSetStatus == null
            ? null
            : () => unawaited(
                onSetStatus!(task, task.status == 'done' ? 'todo' : 'done'),
              ),
        // Icons, not ☑ glyphs: Android draws those as colour emoji.
        icon: Icon(switch (task.status) {
          'doing' => Icons.timelapse,
          'done' => Icons.check_box,
          'cancelled' => Icons.disabled_by_default_outlined,
          _ => Icons.check_box_outline_blank,
        }),
      ),
    ),
  );

  Text _title() => Text(
    task.text,
    style: task.status == 'cancelled' || task.status == 'done'
        ? const TextStyle(decoration: TextDecoration.lineThrough)
        : null,
  );

  Widget _strip() => Builder(
    builder: (context) => TaskChipStrip(
      task: task,
      showEmpty: onSetField != null && !widget.compact,
      onCommand: (field) {
        final box = context.findRenderObject()! as RenderBox;
        _field(context, field, box.localToGlobal(Offset.zero) & box.size);
      },
    ),
  );

  @override
  Widget build(BuildContext context) => widget.compact
      ? InkWell(
          onTap: () => widget.onOpenPath(task.notePath),
          child: Row(
            children: [
              _status(context),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [_title(), _strip()],
                ),
              ),
            ],
          ),
        )
      : ListTile(
          leading: _status(context),
          title: _title(),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.subtitle != null && widget.subtitle!.isNotEmpty)
                Text(widget.subtitle!),
              _strip(),
            ],
          ),
          onTap: () => widget.onOpenPath(task.notePath),
        );
}
