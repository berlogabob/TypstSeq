import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import '../screenshots_ocr.dart';

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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final editable = widget.editable ?? Platform.isMacOS;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const ListTile(
          leading: Icon(Icons.screenshot),
          title: Text('Screenshots (OCR)'),
        ),
        DropdownButton<String>(
          value: mode,
          items: const [
            DropdownMenuItem(value: 'off', child: Text('Off')),
            DropdownMenuItem(value: 'watch', child: Text('Watch')),
            DropdownMenuItem(value: 'schedule', child: Text('Schedule')),
          ],
          onChanged: !editable || busy
              ? null
              : (value) => perform(() async {
                  await widget.onConfigure(value!, time);
                  if (mounted) setState(() => mode = value);
                }),
        ),
        if (mode == 'schedule')
          TextButton(
            onPressed: !editable || busy
                ? null
                : () async {
                    final parts = time.split(':');
                    final picked = await showTimePicker(
                      context: context,
                      initialTime: TimeOfDay(
                        hour: int.tryParse(parts.first) ?? 3,
                        minute: int.tryParse(parts.last) ?? 0,
                      ),
                    );
                    if (picked == null || !mounted) return;
                    final next =
                        '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
                    await perform(() async {
                      await widget.onConfigure(mode, next);
                      if (mounted) setState(() => time = next);
                    });
                  },
            child: Text('Daily at $time'),
          ),
        Text(status),
        TextButton(
          onPressed: busy ? null : () => perform(widget.onProcessNow),
          child: const Text('Process now'),
        ),
      ],
    );
  }
}
