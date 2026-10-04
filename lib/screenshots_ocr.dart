import 'dart:convert';
import 'dart:io';
import 'package:tylog_core/storage.dart';

String screenshotLaunchAgentPlist({
  required String home,
  required String vault,
  required String mode,
  String time = '03:00',
}) {
  String xml(String text) =>
      const HtmlEscape(HtmlEscapeMode.element).convert(text);
  final parts = time.split(':');
  final hour = int.tryParse(parts.first) ?? -1;
  final minute = parts.length == 2 ? int.tryParse(parts.last) ?? -1 : -1;
  if (!['watch', 'schedule'].contains(mode) ||
      hour < 0 ||
      hour > 23 ||
      minute < 0 ||
      minute > 59) {
    throw ArgumentError('Invalid screenshot mode or schedule');
  }
  final args = [
    '/opt/homebrew/bin/uv',
    'run',
    '--directory',
    '$home/Nextcloud/InstantUpload/Screenshots',
    'python',
    if (mode == 'watch') ...[
      'ollama_ocr.py',
      '--watch',
    ] else ...[
      'backfill.py',
      '--vault',
      vault,
    ],
  ];
  return '''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>Label</key><string>org.tylog.screenshots</string>
<key>ProgramArguments</key><array>${args.map((a) => '<string>${xml(a)}</string>').join()}</array>
${mode == 'watch' ? '<key>KeepAlive</key><true/><key>RunAtLoad</key><true/>' : '<key>StartCalendarInterval</key><dict><key>Hour</key><integer>$hour</integer><key>Minute</key><integer>$minute</integer></dict>'}
</dict></plist>''';
}

Future<void> configureScreenshotsOcr(
  String vault,
  String mode,
  String time,
) async {
  if (!Platform.isMacOS) return;
  final home = Platform.environment['HOME']!;
  final plist = mode == 'off'
      ? null
      : screenshotLaunchAgentPlist(
          home: home,
          vault: vault,
          mode: mode,
          time: time,
        );
  if (!['off', 'watch', 'schedule'].contains(mode)) {
    throw ArgumentError('Invalid screenshot mode');
  }
  final uid = (await Process.run('/usr/bin/id', [
    '-u',
  ])).stdout.toString().trim();
  final domain = 'gui/$uid';
  final file = File('$home/Library/LaunchAgents/org.tylog.screenshots.plist');
  await Process.run('/bin/launchctl', [
    'bootout',
    '$domain/org.tylog.screenshots',
  ]);
  if (mode == 'off') {
    if (await file.exists()) await file.delete();
    return;
  }
  await file.parent.create(recursive: true);
  await writeFileAtomic(file, utf8.encode(plist!));
  final result = await Process.run('/bin/launchctl', [
    'bootstrap',
    domain,
    file.path,
  ]);
  if (result.exitCode != 0) throw StateError('launchctl: ${result.stderr}');
}

Future<void> runScreenshotsBackfill(String vault) async {
  final home = Platform.environment['HOME']!;
  // A detached wrapper lets Process.run return immediately while backfill runs.
  final result = await Process.run('/bin/sh', [
    '-c',
    'nohup /opt/homebrew/bin/uv run --directory "\$1" python backfill.py --vault "\$2" >/dev/null 2>&1 </dev/null &',
    'tylog-screenshots',
    '$home/Nextcloud/InstantUpload/Screenshots',
    vault,
  ]);
  if (result.exitCode != 0) {
    throw StateError('Could not start screenshot processing');
  }
}

String screenshotStatusLine(Map<String, dynamic> status) =>
    'Last run: ${status['last_run'] ?? 'Never'} · '
    '${status['processed'] ?? 0} processed · '
    '${status['skipped_sensitive'] ?? 0} sensitive · '
    '${status['duplicates'] ?? 0} duplicates · '
    '${status['errors'] ?? 0} errors · ${status['pending'] ?? 0} pending';

Future<void> requestScreenshotsRun(
  VaultStorage storage, {
  DateTime? now,
}) async {
  await storage.createDirectory('_system/screenshots');
  await storage.writeText(
    '_system/screenshots/run-request.json',
    jsonEncode({
      'requested_at': (now ?? DateTime.now()).toUtc().toIso8601String(),
    }),
  );
}
