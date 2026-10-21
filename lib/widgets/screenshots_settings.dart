import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
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
    this.folder,
    this.onFolderChanged,
    this.readWanted,
  });
  final String mode;
  final String time;
  final bool? editable;
  final String? folder;
  final Future<void> Function(String)? onFolderChanged;
  final Future<void> Function(String, String) onConfigure;
  final Future<void> Function() onProcessNow;
  final Future<String> Function() readStatus;

  /// The mode/time wanted in the synced settings, so a phone shows (and
  /// changes) what the Mac runs.
  final Future<(String, String)?> Function()? readWanted;
  @override
  State<ScreenshotsSettings> createState() => _ScreenshotsSettingsState();
}

class _ScreenshotsSettingsState extends State<ScreenshotsSettings> {
  late String mode = widget.mode;
  late String time = widget.time;
  String status = 'Loading status…';
  String? health;
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
    if (widget.readWanted case final read?) {
      try {
        final wanted = await read();
        if (wanted != null && mounted && !busy) {
          setState(() {
            mode = wanted.$1;
            time = wanted.$2;
          });
        }
      } catch (_) {}
    }
    // Real Mac state (installed agents, health file); skipped in tests, which
    // run on a Mac host and must not read this machine's home folder.
    if (Platform.isMacOS && !Platform.environment.containsKey('FLUTTER_TEST')) {
      final home = Platform.environment['HOME'];
      final folder = widget.folder ?? defaultScreenshotsFolder(home!);
      String? line = screenshotScriptsHealth(folder);
      try {
        line ??= screenshotHealthLine(
          (jsonDecode(
                    await File(
                      '$folder/screenshots-health.json',
                    ).readAsString(),
                  )
                  as Map)
              .cast<String, dynamic>(),
        );
      } catch (_) {}
      String? installed;
      try {
        installed = await installedScreenshotMode();
      } catch (_) {}
      if (mounted) {
        setState(() {
          health = line;
          if (installed != null) mode = installed;
        });
      }
    }
    // Only where the synced setting is wired (the app); the Mac runs it.
    if (widget.readWanted != null && !Platform.isMacOS && mounted) {
      setState(
        () => health = 'Runs on your Mac; changes apply there after sync.',
      );
    }
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
    // "Right after it is added" runs the watcher plus the nightly catch-up
    // (mode both), which retries anything that failed during the day.
    final fly = mode == 'watch' || mode == 'both';
    final sched = mode == 'schedule';
    return Column(
      children: [
        ProcessingPolicyEditor(
          icon: AppIcons.screenshot,
          title: 'Screenshots (OCR)',
          onTheFly: fly,
          scheduled: sched,
          time: time,
          enabled: editable,
          busy: busy,
          status: health == null ? status : '$status\n$health',
          onChanged: (nextFly, nextSched, nextTime) {
            final next = nextFly
                ? 'both'
                : nextSched
                ? 'schedule'
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
        ),
        if (editable && widget.onFolderChanged != null)
          ListTile(
            title: const Text('Screenshot folder'),
            subtitle: Text(
              widget.folder ?? '~/Nextcloud/InstantUpload/Screenshots',
            ),
            trailing: const Icon(Icons.folder_open),
            onTap: () async {
              final path = await FilePicker.getDirectoryPath();
              if (path != null) {
                await perform(() => widget.onFolderChanged!(path));
              }
            },
          ),
      ],
    );
  }
}
