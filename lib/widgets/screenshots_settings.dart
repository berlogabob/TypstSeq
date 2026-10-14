import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'app_icons.dart';
import '../screenshots_ocr.dart';
import 'processing_policy_editor.dart';
import 'snack.dart';

class ScreenshotsSettings extends StatefulWidget {
  const ScreenshotsSettings({
    super.key,
    required this.mode,
    required this.time,
    required this.onConfigure,
    required this.onProcessNow,
    required this.readStatus,
    this.editable,
  });
  final String mode;
  final String time;
  final bool? editable;
  final Future<void> Function(String, String) onConfigure;
  final Future<void> Function() onProcessNow;
  final Future<String> Function() readStatus;
  @override
  State<ScreenshotsSettings> createState() => _ScreenshotsSettingsState();
}

class _ScreenshotsSettingsState extends State<ScreenshotsSettings> {
  late String mode = widget.mode;
  late String time = widget.time;
  String status = 'Loading status…';
  bool busy = false;
  Timer? timer;
  @override
  void initState() {
    super.initState();
    unawaited(refresh());
    timer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => unawaited(refresh()),
    );
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  Future<void> refresh() async {
    String next;
    try {
      next = screenshotStatusLine(
        (jsonDecode(await widget.readStatus()) as Map).cast<String, dynamic>(),
      );
    } catch (_) {
      next = 'No screenshot status available';
    }
    if (mounted) setState(() => status = next);
  }

  Future<void> perform(Future<void> Function() action) async {
    setState(() => busy = true);
    try {
      await action();
      await refresh();
    } catch (error) {
      if (mounted) {
        showSnack(context, '$error');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final editable = widget.editable ?? Platform.isMacOS;
    final fly = mode == 'watch';
    final sched = mode == 'schedule' || mode == 'both';
    return ProcessingPolicyEditor(
      icon: AppIcons.screenshot,
      title: 'Screenshots (OCR)',
      onTheFly: fly,
      scheduled: sched,
      time: time,
      enabled: editable,
      busy: busy,
      status: status,
      onChanged: (nextFly, nextSched, nextTime) {
        final next = nextSched
            ? 'schedule'
            : nextFly
            ? 'watch'
            : 'off';
        unawaited(
          perform(() async {
            await widget.onConfigure(next, nextTime);
            if (mounted) {
              setState(() {
                mode = next;
                time = nextTime;
              });
            }
          }),
        );
      },
      onProcessNow: () => unawaited(perform(widget.onProcessNow)),
    );
  }
}
