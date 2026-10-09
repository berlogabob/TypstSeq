import 'dart:async';

import 'package:flutter/material.dart';
import 'constants.dart';

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
    this.onStop,
  });

  final TaskRef task;
  final VoidCallback onOpen;
  final Future<void> Function(TaskRef)? onStop;

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
    return Row(
      mainAxisSize: MainAxisSize.max,
      children: [
        Expanded(
          child: InkWell(
            onTap: widget.onOpen,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: kMinTapTarget),
              child: Align(
                alignment: Alignment.centerLeft,
                heightFactor: 1,
                child: Text(
                  widget.task.text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ),
        ),
        if (running != null) ...[
          const SizedBox(width: kSpace8),
          Text(timerTime(elapsed)),
        ],
        if (widget.onStop != null)
          IconButton(
            tooltip: 'Stop timer',
            icon: const Icon(Icons.stop),
            onPressed: () => unawaited(widget.onStop!(widget.task)),
          ),
      ],
    );
  }
}
