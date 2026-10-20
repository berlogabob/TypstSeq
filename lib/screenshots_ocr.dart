import 'dart:convert';
import 'dart:io';
import 'package:tylog_core/storage.dart';

String screenshotLaunchAgentPlist({
  required String home,
  required String vault,
  required String mode,
  String? scriptsDir,
  String? uvPath,
  String time = '03:00',
  String label = 'org.tylog.screenshots',
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
  final folder = scriptsDir ?? defaultScreenshotsFolder(home);
  final args = [
    uvPath ?? '/opt/homebrew/bin/uv',
    'run',
    '--directory',
    folder,
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
<key>Label</key><string>${xml(label)}</string>
<key>StandardOutPath</key><string>${xml('$folder/$label.log')}</string>
<key>StandardErrorPath</key><string>${xml('$folder/$label.log')}</string>
<key>ProgramArguments</key><array>${args.map((a) => '<string>${xml(a)}</string>').join()}</array>
${mode == 'watch' ? '<key>KeepAlive</key><true/><key>RunAtLoad</key><true/>' : '<key>StartCalendarInterval</key><dict><key>Hour</key><integer>$hour</integer><key>Minute</key><integer>$minute</integer></dict>'}
</dict></plist>''';
}

/// Where the screenshot scripts live when the user has not picked a folder.
String defaultScreenshotsFolder(String home) =>
    '$home/Nextcloud/InstantUpload/Screenshots';

/// First uv binary found: Homebrew, /usr/local, then the user's own installs.
/// LaunchAgents get no login PATH, so the plist needs the absolute path.
Future<String?> findUv({
  String? home,
  List<String> system = const ['/opt/homebrew/bin/uv', '/usr/local/bin/uv'],
}) async {
  final dir = home ?? Platform.environment['HOME'];
  for (final path in [
    ...system,
    if (dir != null) '$dir/.local/bin/uv',
    if (dir != null) '$dir/.cargo/bin/uv',
  ]) {
    if (await File(path).exists()) return path;
  }
  return null;
}

/// Null when the folder holds the scripts, else a line for the settings status.
String? screenshotScriptsHealth(String folder) =>
    File('$folder/ollama_ocr.py').existsSync()
    ? null
    : 'Screenshot scripts not found in $folder';

/// Inspects which LaunchAgents are installed to report the active screenshot
/// OCR mode. Returns 'both' if both agents exist, 'watch' if only the watch
/// agent exists and runs ollama OCR, 'schedule' if only the watch agent exists
/// and runs backfill (or only the schedule agent exists), else 'off'.
Future<String> installedScreenshotMode({String? home}) async {
  final homeDir = home ?? Platform.environment['HOME']!;
  final watch = File(
    '$homeDir/Library/LaunchAgents/org.tylog.screenshots.plist',
  );
  final schedule = File(
    '$homeDir/Library/LaunchAgents/org.tylog.screenshots.schedule.plist',
  );
  final watchExists = await watch.exists();
  final scheduleExists = await schedule.exists();
  if (watchExists && scheduleExists) return 'both';
  if (watchExists) {
    final content = await watch.readAsString();
    return content.contains('ollama_ocr.py') ? 'watch' : 'schedule';
  }
  if (scheduleExists) {
    final content = await schedule.readAsString();
    if (content.contains('backfill.py')) return 'schedule';
  }
  return 'off';
}

String? screenshotHealthLine(Map<String, dynamic>? json) {
  if (json == null || json['checked_at'] is! String) return null;
  final checkedAt = json['checked_at'] as String;
  if (checkedAt.isEmpty || json['ok'] is! bool) return null;
  if (json['ok'] == true) {
    return 'Screenshots up to date (checked $checkedAt)';
  }
  final lagHours = json['lag_hours'];
  final newestUpload = json['newest_upload'];
  if (lagHours is! num || newestUpload is! String || newestUpload.isEmpty) {
    return null;
  }
  return 'Screenshots behind by ${lagHours.round()} h, newest upload $newestUpload';
}

/// off | watch (on the fly) | schedule (daily) | both (one agent each).
Future<void> configureScreenshotsOcr(
  String vault,
  String mode,
  String time, {
  String? scriptsDir,
}) async {
  if (!Platform.isMacOS) return;
  if (!['off', 'watch', 'schedule', 'both'].contains(mode)) {
    throw ArgumentError('Invalid screenshot mode');
  }
  final home = Platform.environment['HOME']!;
  final folder = scriptsDir ?? defaultScreenshotsFolder(home);
  final uv = await findUv();
  if (uv == null) throw StateError('uv not found on PATH');
  const watchLabel = 'org.tylog.screenshots';
  const scheduleLabel = 'org.tylog.screenshots.schedule';
  // (label, agent mode). A lone schedule keeps the original label.
  final agents = [
    if (mode == 'watch' || mode == 'both') (watchLabel, 'watch'),
    if (mode == 'schedule') (watchLabel, 'schedule'),
    if (mode == 'both') (scheduleLabel, 'schedule'),
  ];
  // Build every plist first: a bad time must not leave agents half removed.
  final plists = [
    for (final (label, agentMode) in agents)
      (
        label,
        screenshotLaunchAgentPlist(
          home: home,
          vault: vault,
          mode: agentMode,
          time: time,
          label: label,
          scriptsDir: folder,
          uvPath: uv,
        ),
      ),
  ];
  final uid = (await Process.run('/usr/bin/id', [
    '-u',
  ])).stdout.toString().trim();
  final domain = 'gui/$uid';
  File fileFor(String label) => File('$home/Library/LaunchAgents/$label.plist');
  for (final label in [watchLabel, scheduleLabel]) {
    await Process.run('/bin/launchctl', ['bootout', '$domain/$label']);
    if (await fileFor(label).exists()) await fileFor(label).delete();
  }
  for (final (label, plist) in plists) {
    final file = fileFor(label);
    await file.parent.create(recursive: true);
    await writeFileAtomic(file, utf8.encode(plist));
    final result = await Process.run('/bin/launchctl', [
      'bootstrap',
      domain,
      file.path,
    ]);
    if (result.exitCode != 0) throw StateError('launchctl: ${result.stderr}');
  }
}

Future<void> runScreenshotsBackfill(String vault, {String? scriptsDir}) async {
  final home = Platform.environment['HOME']!;
  final uv = await findUv();
  if (uv == null) throw StateError('uv not found on PATH');
  // A detached wrapper lets Process.run return immediately while backfill runs.
  final result = await Process.run('/bin/sh', [
    '-c',
    'nohup "\$1" run --directory "\$2" python backfill.py --vault "\$3" >/dev/null 2>&1 </dev/null &',
    'tylog-screenshots',
    uv,
    scriptsDir ?? defaultScreenshotsFolder(home),
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
