import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'widgets/app_version.dart';

/// GitHub owner/repo the desktop build is released from.
const _owner = 'berlogabob';
const _repo = 'TypstSeq';

/// The macOS release asset (a `ditto` zip of `TyLog.app`) — a static name, so it
/// also has a stable `releases/latest/download/...` URL as a fallback.
const _macAsset = 'TyLog-macos.zip';
const _windowsAsset = 'TyLog-windows.exe';

/// Digest of [_macAsset], published beside it by the release workflow.
const _macDigestAsset = '$_macAsset.sha256';

const _latestApi =
    'https://api.github.com/repos/$_owner/$_repo/releases/latest';
const _stableMacUrl =
    'https://github.com/$_owner/$_repo/releases/latest/download/$_macAsset';
const _stableMacDigestUrl =
    'https://github.com/$_owner/$_repo/releases/latest/download/$_macDigestAsset';
const _stableWindowsUrl =
    'https://github.com/$_owner/$_repo/releases/latest/download/$_windowsAsset';
const _stableWindowsDigestUrl =
    'https://github.com/$_owner/$_repo/releases/latest/download/$_windowsAsset.sha256';

bool windowsSelfUpdatable([Map<String, String>? env, bool? platformIsWindows]) {
  final environment = env ?? Platform.environment;
  return (platformIsWindows ?? Platform.isWindows) &&
      (environment['TYLOG_LAUNCHER']?.isNotEmpty ?? false);
}

/// A newer release than what's running, ready to download + apply.
class UpdateInfo {
  const UpdateInfo({
    required this.version,
    required this.notes,
    required this.zipUrl,
    required this.digestUrl,
    required this.htmlUrl,
  });

  /// The release version without the leading `v` (e.g. `0.1.0+71`).
  final String version;

  /// Release notes (may be empty).
  final String notes;

  /// Direct download URL for the platform asset.
  final String zipUrl;

  /// URL of the published SHA-256 for [zipUrl].
  final String digestUrl;

  /// The release page, for the manual-install fallback.
  final String htmlUrl;
}

/// Thrown by [downloadAndApply] when the downloaded zip does not match the
/// digest published beside it.
///
/// The updater deletes the running bundle and replaces it, so a truncated or
/// substituted download must stop before anything is touched. This is an
/// integrity check, not an authenticity one: an attacker who can serve a
/// different zip can serve a matching digest too. Real authenticity needs
/// Developer ID signing and notarization, which this build does not do.
class UpdateNotVerified implements Exception {
  const UpdateNotVerified({required this.expected, required this.actual});

  /// The published digest, or null when it could not be fetched.
  final String? expected;
  final String actual;

  @override
  String toString() => expected == null
      ? 'Update could not be verified: no published checksum'
      : 'Update failed verification: expected $expected, got $actual';
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
  String asset = _macAsset,
}) {
  final json = jsonDecode(jsonBody);
  if (json is! Map) return null;
  final tag = (json['tag_name'] as String?)?.trim();
  if (tag == null || tag.isEmpty) return null;
  if (!isNewer(tag, currentVersion)) return null;

  final selectedAsset = asset == 'windows' ? _windowsAsset : asset;
  final digestAsset = '$selectedAsset.sha256';
  final stableUrl = selectedAsset == _windowsAsset
      ? _stableWindowsUrl
      : _stableMacUrl;
  final stableDigestUrl = selectedAsset == _windowsAsset
      ? _stableWindowsDigestUrl
      : _stableMacDigestUrl;
  String? zipUrl;
  String? digestUrl;
  if (json['assets'] case final List assets) {
    for (final a in assets) {
      if (a is! Map) continue;
      if (a['name'] == selectedAsset) {
        zipUrl = a['browser_download_url'] as String?;
      }
      if (a['name'] == digestAsset) {
        digestUrl = a['browser_download_url'] as String?;
      }
    }
  }
  return UpdateInfo(
    version: tag.startsWith('v') ? tag.substring(1) : tag,
    notes: (json['body'] as String?)?.trim() ?? '',
    zipUrl: zipUrl ?? stableUrl,
    digestUrl: digestUrl ?? stableDigestUrl,
    htmlUrl:
        (json['html_url'] as String?) ??
        'https://github.com/$_owner/$_repo/releases/latest',
  );
}

/// Checks GitHub for a newer desktop release. `info` is the newer release (or null
/// when already current / off macOS); `failed` is true only when the check
/// itself couldn't complete (network error or non-200) — distinct from "up to
/// date" so the caller can report accurately. [currentVersion] defaults to
/// [appVersion].
Future<({UpdateInfo? info, bool failed})> checkForUpdate({
  HttpClient? client,
  String? currentVersion,
}) async {
  final windows = windowsSelfUpdatable();
  if (!Platform.isMacOS && !windows) return (info: null, failed: false);
  final current = currentVersion ?? await appVersion();
  final http = client ?? HttpClient()
    ..connectionTimeout = const Duration(seconds: 15);
  try {
    final request = await http.getUrl(Uri.parse(_latestApi));
    request.headers.set(HttpHeaders.userAgentHeader, 'TyLog-Updater');
    request.headers.set(
      HttpHeaders.acceptHeader,
      'application/vnd.github+json',
    );
    final response = await request.close();
    if (response.statusCode != 200) return (info: null, failed: true);
    final body = await response.transform(utf8.decoder).join();
    return (
      info: parseLatestRelease(
        body,
        currentVersion: current,
        asset: windows ? _windowsAsset : _macAsset,
      ),
      failed: false,
    );
  } on Exception {
    return (info: null, failed: true);
  } finally {
    if (client == null) http.close(force: true);
  }
}

/// Downloads the update, verifies it against the digest published beside it,
/// then hands off to a detached helper that waits for this process to quit,
/// swaps the `.app` in place (quarantine stripped), or replaces the Windows
/// launcher, and relaunches — after which this process exits.
///
/// Throws [UpdateNotWritable] before downloading if the app can't be replaced,
/// and [UpdateNotVerified] after downloading if the bytes don't match. Nothing
/// on disk is touched until the download verifies.
Future<void> downloadAndApply(
  UpdateInfo info, {
  void Function(double progress)? onProgress,
}) async {
  final windows = windowsSelfUpdatable();
  if (!Platform.isMacOS && !windows) return;

  if (windows) {
    final launcherPath = Platform.environment['TYLOG_LAUNCHER']!;
    final newPath =
        '${Directory.systemTemp.path}/TyLog-update-${info.version}.exe';
    final helperPath = '${Directory.systemTemp.path}/tylog-update.cmd';
    final http = HttpClient()..connectionTimeout = const Duration(seconds: 30);
    try {
      final request = await http.getUrl(Uri.parse(info.zipUrl));
      request.headers.set(HttpHeaders.userAgentHeader, 'TyLog-Updater');
      final response = await request.close();
      if (response.statusCode != 200) {
        throw HttpException(
          'HTTP ${response.statusCode}',
          uri: Uri.parse(info.zipUrl),
        );
      }
      final total = response.contentLength;
      final sink = File(newPath).openWrite();
      var received = 0;
      await for (final chunk in response) {
        received += chunk.length;
        sink.add(chunk);
        if (total > 0) onProgress?.call(received / total);
      }
      await sink.close();
      final expected = await _fetchDigest(info.digestUrl, http);
      final actual = sha256
          .convert(await File(newPath).readAsBytes())
          .toString();
      if (expected == null || expected != actual) {
        throw UpdateNotVerified(expected: expected, actual: actual);
      }
    } catch (_) {
      final downloaded = File(newPath);
      if (downloaded.existsSync()) downloaded.deleteSync();
      rethrow;
    } finally {
      http.close(force: true);
    }
    onProgress?.call(1);
    await File(helperPath).writeAsString(windowsUpdateScript());
    await Process.start(
      'cmd',
      ['/c', helperPath, '$pid', newPath, launcherPath],
      mode: ProcessStartMode.detached,
      runInShell: false,
    );
    exit(0);
  }

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

  // A private 0700 directory rather than a predictable name in world-writable
  // /tmp: the helper script below runs as the user, and anything that can
  // rewrite it between the write and the exec gets to run whatever it likes.
  final work = Directory.systemTemp.createTempSync('tylog-update-');
  final zipPath = '${work.path}/$_macAsset';

  // Stream the zip to a temp file, reporting progress.
  final http = HttpClient()..connectionTimeout = const Duration(seconds: 30);
  try {
    final request = await http.getUrl(Uri.parse(info.zipUrl));
    request.headers.set(HttpHeaders.userAgentHeader, 'TyLog-Updater');
    final response = await request.close();
    if (response.statusCode != 200) {
      throw HttpException(
        'HTTP ${response.statusCode}',
        uri: Uri.parse(info.zipUrl),
      );
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
    final expected = await _fetchDigest(info.digestUrl, http);
    final actual = sha256.convert(await File(zipPath).readAsBytes()).toString();
    if (expected == null || expected != actual) {
      throw UpdateNotVerified(expected: expected, actual: actual);
    }
  } catch (_) {
    work.deleteSync(recursive: true);
    rethrow;
  } finally {
    http.close(force: true);
  }
  onProgress?.call(1);

  // Detached helper: wait for us to exit, unzip with `ditto` (preserves the
  // bundle's exec bits + framework symlinks), swap, strip quarantine, relaunch.
  //
  // The old bundle is moved aside, not deleted, and only removed once the new
  // one is in place — `rm -rf "$APP" && ditto ...` left the user with no app at
  // all if the copy failed halfway. On any failure the previous bundle is put
  // back and relaunched.
  final scriptPath = '${work.path}/apply.sh';
  await File(scriptPath).writeAsString('''
#!/bin/bash
PID="\$1"; ZIP="\$2"; APP="\$3"; WORK="\$4"; STAGE="\$(mktemp -d)"
while kill -0 "\$PID" 2>/dev/null; do sleep 0.2; done
/usr/bin/ditto -x -k "\$ZIP" "\$STAGE" || exit 1
NEW="\$(/bin/ls -d "\$STAGE"/*.app 2>/dev/null | head -1)"
[ -z "\$NEW" ] && exit 1
/usr/bin/xattr -dr com.apple.quarantine "\$NEW" 2>/dev/null
BACKUP="\$APP.previous-\$\$"
mv "\$APP" "\$BACKUP" || exit 1
if /usr/bin/ditto "\$NEW" "\$APP"; then
  rm -rf "\$BACKUP"
else
  rm -rf "\$APP"
  mv "\$BACKUP" "\$APP"
fi
/usr/bin/xattr -dr com.apple.quarantine "\$APP" 2>/dev/null
/usr/bin/open "\$APP"
rm -rf "\$STAGE" "\$WORK"
''');

  await Process.start('/bin/bash', [
    scriptPath,
    '$pid',
    zipPath,
    appPath,
    work.path,
  ], mode: ProcessStartMode.detached);
  // Quit so the helper can replace the running bundle.
  await Future<void>.delayed(const Duration(milliseconds: 200));
  exit(0);
}

// %~2/%~3 strip the quotes the paths arrive with (spaces in user names);
// `ping` pauses where `timeout` refuses to run (detached: no console).
String windowsUpdateScript() => r'''@echo off
title TyLog update
set LOG=%TEMP%\tylog-update.log
echo %date% %time% waiting for pid %1 >> "%LOG%"
set /a n=0
:wait
tasklist /FI "PID eq %1" /FO CSV /NH | find """%1""" >nul
if errorlevel 1 goto gone
set /a n+=1
rem A process that ignores exit() is ended after a few seconds; give up at 2 min.
if %n% GEQ 8 taskkill /F /PID %1 >> "%LOG%" 2>&1
if %n% GEQ 60 goto gone
ping -n 2 127.0.0.1 >nul
goto wait
:gone
set /a m=0
:swap
move /y "%~2" "%~3" >> "%LOG%" 2>&1 && goto done
set /a m+=1
if %m% GEQ 20 goto failed
ping -n 2 127.0.0.1 >nul
goto swap
:failed
echo %date% %time% could not replace %~3 >> "%LOG%"
:done
echo %date% %time% starting %~3 >> "%LOG%"
start "" "%~3"
del "%~f0"
''';

/// Fetches the published SHA-256 for the macOS asset, or null if unavailable.
///
/// The file holds the bare lowercase hex digest, one line, as written by
/// `shasum -a 256 ... | awk '{print $1}'` in the release workflow.
Future<String?> _fetchDigest(String url, HttpClient http) async {
  try {
    final request = await http.getUrl(Uri.parse(url));
    request.headers.set(HttpHeaders.userAgentHeader, 'TyLog-Updater');
    final response = await request.close();
    if (response.statusCode != 200) return null;
    final body = (await response.transform(utf8.decoder).join()).trim();
    final digest = body.split(RegExp(r'\s+')).first.toLowerCase();
    return RegExp(r'^[0-9a-f]{64}$').hasMatch(digest) ? digest : null;
  } on Exception {
    return null;
  }
}
