import 'dart:async';

import 'package:flutter/material.dart';

import '../models.dart';

String trackedTime(Duration duration) {
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);
  if (hours > 0) return '${hours}h${minutes > 0 ? ' ${minutes}m' : ''}';
  return duration.inMinutes > 0
      ? '${duration.inMinutes}m'
      : '${duration.inSeconds}s';
}

String timerTime(Duration duration) {
  final seconds = duration.isNegative ? 0 : duration.inSeconds;
  final minutes = (seconds ~/ 60).remainder(60).toString().padLeft(2, '0');
  final tail = seconds.remainder(60).toString().padLeft(2, '0');
  return seconds >= 3600
      ? '${seconds ~/ 3600}:$minutes:$tail'
      : '$minutes:$tail';
}

class TaskClock extends StatefulWidget {
  const TaskClock({
    super.key,
    required this.task,
    required this.onOpen,
    this.onToggle,
    this.pill = false,
  });

  final TaskRef task;
  final VoidCallback onOpen;
  final Future<void> Function(TaskRef)? onToggle;
  final bool pill;

  @override
  State<TaskClock> createState() => _TaskClockState();
}

class _TaskClockState extends State<TaskClock> with WidgetsBindingObserver {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _updateTicker();
  }

  @override
  void didUpdateWidget(TaskClock oldWidget) {
    super.didUpdateWidget(oldWidget);
    _updateTicker();
  }

  void _updateTicker() {
    _ticker?.cancel();
    _ticker = null;
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (widget.task.runningClock != null &&
        (lifecycle == null || lifecycle == AppLifecycleState.resumed)) {
      _ticker = Timer.periodic(
        const Duration(seconds: 1),
        (_) => setState(() {}),
      );
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _updateTicker();
    if (state == AppLifecycleState.resumed) setState(() {});
  }

  @override
  void dispose() {
    _ticker?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final running = widget.task.runningClock;
    final start = running == null ? null : DateTime.tryParse(running.start);
    final elapsed = start == null
        ? Duration.zero
        : DateTime.now().difference(start);
    final total = widget.task.clockedTotal;
    return Row(
      mainAxisSize: widget.pill ? MainAxisSize.max : MainAxisSize.min,
      children: [
        if (widget.pill)
          Expanded(
            child: InkWell(
              onTap: widget.onOpen,
              child: Text(
                widget.task.text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        if (!widget.pill && total > Duration.zero)
          Text(
            trackedTime(total),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        if (running != null) ...[
          const SizedBox(width: 8),
          Text(timerTime(elapsed)),
        ],
        if (widget.onToggle != null)
          IconButton(
            tooltip: running == null ? 'Start timer' : 'Stop timer',
            icon: Icon(running == null ? Icons.play_arrow : Icons.stop),
            onPressed: () => unawaited(widget.onToggle!(widget.task)),
          ),
        if (!widget.pill)
          IconButton(
            tooltip: 'Open source note',
            icon: const Icon(Icons.open_in_new),
            onPressed: widget.onOpen,
          ),
      ],
    );
  }
}
