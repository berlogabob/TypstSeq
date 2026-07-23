import 'dart:convert';
import 'dart:io';

import 'widgets/app_version.dart';

/// GitHub owner/repo the desktop build is released from.
const _owner = 'berlogabob';
const _repo = 'TypstSeq';

/// The macOS release asset (a `ditto` zip of `TyLog.app`) — a static name, so it
/// also has a stable `releases/latest/download/...` URL as a fallback.
const _macAsset = 'TyLog-macos.zip';

const _latestApi = 'https://api.github.com/repos/$_owner/$_repo/releases/latest';
const _stableMacUrl =
    'https://github.com/$_owner/$_repo/releases/latest/download/$_macAsset';

/// A newer release than what's running, ready to download + apply.
class UpdateInfo {
  const UpdateInfo({
    required this.version,
    required this.notes,
    required this.zipUrl,
    required this.htmlUrl,
  });

  /// The release version without the leading `v` (e.g. `0.1.0+71`).
  final String version;

  /// Release notes (may be empty).
  final String notes;

  /// Direct download URL for the macOS asset.
  final String zipUrl;

  /// The release page, for the manual-install fallback.
  final String htmlUrl;
}

/// Thrown by [downloadAndApply] when the running `.app` sits in a directory we
/// can't write — the caller should fall back to opening the release page.
class UpdateNotWritable implements Exception {
  const UpdateNotWritable(this.appPath);
  final String appPath;
  @override
  String toString() => 'App location is not writable: $appPath';
}

/// Parses `X.Y.Z+N` (optionally `v`-prefixed; missing `+N` ⇒ build 0). Unknown
/// fields default to 0 so a malformed string simply sorts oldest.
({int major, int minor, int patch, int build}) parseVersion(String raw) {
  var s = raw.trim();
  if (s.startsWith('v')) s = s.substring(1);
  final plus = s.split('+');
  final build = plus.length > 1 ? (int.tryParse(plus[1].trim()) ?? 0) : 0;
  final parts = plus[0].split('.');
  int at(int i) => i < parts.length ? (int.tryParse(parts[i].trim()) ?? 0) : 0;
  return (major: at(0), minor: at(1), patch: at(2), build: build);
}

/// True when [candidate] is a strictly newer version than [current] (semver
/// triple first, then build number).
bool isNewer(String candidate, String current) {
  final a = parseVersion(candidate);
  final b = parseVersion(current);
  for (final d in [
    a.major - b.major,
    a.minor - b.minor,
    a.patch - b.patch,
    a.build - b.build,
  ]) {
    if (d != 0) return d > 0;
  }
  return false;
}

/// Parses a GitHub "latest release" API body and returns an [UpdateInfo] only if
/// its tag is newer than [currentVersion]; otherwise null. Pure — no I/O.
UpdateInfo? parseLatestRelease(
  String jsonBody, {
  required String currentVersion,
}) {
  final json = jsonDecode(jsonBody);
  if (json is! Map) return null;
  final tag = (json['tag_name'] as String?)?.trim();
  if (tag == null || tag.isEmpty) return null;
  if (!isNewer(tag, currentVersion)) return null;

  String? zipUrl;
  if (json['assets'] case final List assets) {
    for (final a in assets) {
      if (a is Map && a['name'] == _macAsset) {
        zipUrl = a['browser_download_url'] as String?;
        break;
      }
    }
  }
  return UpdateInfo(
    version: tag.startsWith('v') ? tag.substring(1) : tag,
    notes: (json['body'] as String?)?.trim() ?? '',
    zipUrl: zipUrl ?? _stableMacUrl,
    htmlUrl:
        (json['html_url'] as String?) ??
        'https://github.com/$_owner/$_repo/releases/latest',
  );
}

/// Checks GitHub for a newer macOS release. Returns null off macOS, on network
/// error, or when already up to date. [currentVersion] defaults to [appVersion].
Future<UpdateInfo?> checkForUpdate({
  HttpClient? client,
  String? currentVersion,
}) async {
  if (!Platform.isMacOS) return null;
  final current = currentVersion ?? await appVersion();
  final http = client ?? HttpClient()
    ..connectionTimeout = const Duration(seconds: 15);
  try {
    final request = await http.getUrl(Uri.parse(_latestApi));
    request.headers.set(HttpHeaders.userAgentHeader, 'TyLog-Updater');
    request.headers.set(HttpHeaders.acceptHeader, 'application/vnd.github+json');
    final response = await request.close();
    if (response.statusCode != 200) return null;
    final body = await response.transform(utf8.decoder).join();
    return parseLatestRelease(body, currentVersion: current);
  } on Exception {
    return null;
  } finally {
    if (client == null) http.close(force: true);
  }
}

/// Downloads the update, then hands off to a detached helper that waits for this
/// process to quit, swaps the `.app` in place (quarantine stripped), and
/// relaunches — after which this process exits. macOS only.
///
/// Throws [UpdateNotWritable] before downloading if the app can't be replaced.
Future<void> downloadAndApply(
  UpdateInfo info, {
  void Function(double progress)? onProgress,
}) async {
  if (!Platform.isMacOS) return;

  // …/TyLog.app/Contents/MacOS/TyLog → walk up 3 to the bundle root.
  final exe = File(Platform.resolvedExecutable);
  final appPath = exe.parent.parent.parent.path;
  if (!appPath.endsWith('.app')) {
    throw UpdateNotWritable(appPath); // running unbundled (e.g. `flutter run`)
  }
  final parent = File(appPath).parent.path;
  final probe = File('$parent/.tylog_update_probe');
  try {
    probe.writeAsStringSync('x');
    probe.deleteSync();
  } on FileSystemException {
    throw UpdateNotWritable(appPath);
  }

  // Stream the zip to a temp file, reporting progress.
  final http = HttpClient()..connectionTimeout = const Duration(seconds: 30);
  final zipPath =
      '${Directory.systemTemp.path}/tylog-update-${DateTime.now().millisecondsSinceEpoch}.zip';
  try {
    final request = await http.getUrl(Uri.parse(info.zipUrl));
    request.headers.set(HttpHeaders.userAgentHeader, 'TyLog-Updater');
    final response = await request.close();
    if (response.statusCode != 200) {
      throw HttpException('HTTP ${response.statusCode}', uri: Uri.parse(info.zipUrl));
    }
    final total = response.contentLength;
    final sink = File(zipPath).openWrite();
    var received = 0;
    await for (final chunk in response) {
      received += chunk.length;
      sink.add(chunk);
      if (total > 0) onProgress?.call(received / total);
    }
    await sink.close();
  } finally {
    http.close(force: true);
  }
  onProgress?.call(1);

  // Detached helper: wait for us to exit, unzip with `ditto` (preserves the
  // bundle's exec bits + framework symlinks), swap, strip quarantine, relaunch.
  final scriptPath =
      '${Directory.systemTemp.path}/tylog-update-${DateTime.now().millisecondsSinceEpoch}.sh';
  await File(scriptPath).writeAsString('''
#!/bin/bash
PID="\$1"; ZIP="\$2"; APP="\$3"; STAGE="\$(mktemp -d)"
while kill -0 "\$PID" 2>/dev/null; do sleep 0.2; done
/usr/bin/ditto -x -k "\$ZIP" "\$STAGE" || exit 1
NEW="\$(/bin/ls -d "\$STAGE"/*.app 2>/dev/null | head -1)"
[ -z "\$NEW" ] && exit 1
/usr/bin/xattr -dr com.apple.quarantine "\$NEW" 2>/dev/null
rm -rf "\$APP" && /usr/bin/ditto "\$NEW" "\$APP" || exit 1
/usr/bin/xattr -dr com.apple.quarantine "\$APP" 2>/dev/null
/usr/bin/open "\$APP"
rm -rf "\$STAGE" "\$ZIP" "\$0"
''');

  await Process.start(
    '/bin/bash',
    [scriptPath, '$pid', zipPath, appPath],
    mode: ProcessStartMode.detached,
  );
  // Quit so the helper can replace the running bundle.
  await Future<void>.delayed(const Duration(milliseconds: 200));
  exit(0);
}
