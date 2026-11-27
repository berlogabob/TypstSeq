import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/desktop_updater.dart';

String _release({
  required String tag,
  bool withMacAsset = true,
  bool withDigestAsset = true,
  bool withWindowsAsset = false,
  bool withWindowsDigestAsset = false,
  String body = 'Notes here',
}) => jsonEncode({
  'tag_name': tag,
  'html_url': 'https://github.com/berlogabob/TypstSeq/releases/tag/$tag',
  'body': body,
  'assets': [
    {'name': 'tylog-android.apk', 'browser_download_url': 'https://x/apk'},
    if (withMacAsset)
      {
        'name': 'TyLog-macos.zip',
        'browser_download_url': 'https://x/TyLog-macos.zip',
      },
    if (withDigestAsset)
      {
        'name': 'TyLog-macos.zip.sha256',
        'browser_download_url': 'https://x/TyLog-macos.zip.sha256',
      },
    if (withWindowsAsset)
      {
        'name': 'TyLog-windows.exe',
        'browser_download_url': 'https://x/TyLog-windows.exe',
      },
    if (withWindowsDigestAsset)
      {
        'name': 'TyLog-windows.exe.sha256',
        'browser_download_url': 'https://x/TyLog-windows.exe.sha256',
      },
  ],
});

void main() {
  group('version parsing/compare', () {
    test('parses v-prefixed semver+build', () {
      final v = parseVersion('v0.1.0+71');
      expect((v.major, v.minor, v.patch, v.build), (0, 1, 0, 71));
    });

    test('missing build defaults to 0', () {
      expect(parseVersion('1.2.3').build, 0);
    });

    test('isNewer covers build, patch, equal, older', () {
      expect(isNewer('0.1.0+71', '0.1.0+70'), isTrue); // build bump
      expect(isNewer('0.2.0+1', '0.1.9+99'), isTrue); // minor bump wins
      expect(isNewer('0.1.0+70', '0.1.0+70'), isFalse); // equal
      expect(isNewer('0.1.0+69', '0.1.0+70'), isFalse); // older
      expect(isNewer('v0.1.0+71', '0.1.0+70'), isTrue); // tolerates v-prefix
    });
  });

  group('parseLatestRelease', () {
    test('returns UpdateInfo with the mac asset URL when newer', () {
      final info = parseLatestRelease(
        _release(tag: 'v0.1.0+71'),
        currentVersion: '0.1.0+70',
      );
      expect(info, isNotNull);
      expect(info!.version, '0.1.0+71');
      expect(info.notes, 'Notes here');
      expect(info.zipUrl, 'https://x/TyLog-macos.zip');
    });

    test('null when the latest tag is not newer', () {
      expect(
        parseLatestRelease(
          _release(tag: 'v0.1.0+70'),
          currentVersion: '0.1.0+70',
        ),
        isNull,
      );
    });

    test('falls back to the stable-latest URL when the mac asset is absent', () {
      final info = parseLatestRelease(
        _release(tag: 'v0.1.0+71', withMacAsset: false),
        currentVersion: '0.1.0+70',
      );
      expect(info, isNotNull);
      expect(
        info!.zipUrl,
        'https://github.com/berlogabob/TypstSeq/releases/latest/download/TyLog-macos.zip',
      );
    });
  });

  group('update verification', () {
    // The updater deletes the running bundle and replaces it, so it has to be
    // able to tell a complete download from a truncated or substituted one
    // before it touches anything.
    test('the published digest is found alongside the zip', () {
      final info = parseLatestRelease(
        _release(tag: 'v0.1.0+90'),
        currentVersion: '0.1.0+89',
      );

      expect(info!.zipUrl, 'https://x/TyLog-macos.zip');
      expect(info.digestUrl, 'https://x/TyLog-macos.zip.sha256');
    });

    // An older release has the zip but no digest beside it. Falling back to the
    // stable URL keeps the updater working rather than wedging it — and if that
    // URL 404s, verification fails closed.
    test('a release without a digest asset falls back to the stable URL', () {
      final info = parseLatestRelease(
        _release(tag: 'v0.1.0+90', withDigestAsset: false),
        currentVersion: '0.1.0+89',
      );

      expect(
        info!.digestUrl,
        'https://github.com/berlogabob/TypstSeq/releases/latest/download/'
        'TyLog-macos.zip.sha256',
      );
    });

    test('a missing checksum reads as unverified, not as verified', () {
      const missing = UpdateNotVerified(expected: null, actual: 'abc');

      expect('$missing', contains('no published checksum'));
    });

    test('a mismatch names both digests', () {
      const mismatch = UpdateNotVerified(expected: 'aaa', actual: 'bbb');

      expect('$mismatch', contains('expected aaa'));
      expect('$mismatch', contains('got bbb'));
    });
  });

  group('Windows updater', () {
    test('selects the Windows assets', () {
      final info = parseLatestRelease(
        _release(
          tag: 'v0.1.0+91',
          withWindowsAsset: true,
          withWindowsDigestAsset: true,
        ),
        currentVersion: '0.1.0+90',
        asset: 'windows',
      );

      expect(info!.zipUrl, 'https://x/TyLog-windows.exe');
      expect(info.digestUrl, 'https://x/TyLog-windows.exe.sha256');
    });

    test('is enabled only for a Windows launcher build', () {
      expect(windowsSelfUpdatable({}, true), isFalse);
      expect(
        windowsSelfUpdatable({'TYLOG_LAUNCHER': r'C:\TyLog.exe'}, true),
        isTrue,
      );
    });

    test(
      'script waits, kills a stuck process, replaces, relaunches, deletes',
      () {
        final script = windowsUpdateScript();
        expect(
          script,
          contains(r'tasklist.exe" /FI "PID eq %1" /FO CSV /NH > "%TASKS%"'),
        );
        expect(script, isNot(contains('| find')));
        expect(script, contains(r'taskkill.exe" /F /PID %1'));
        expect(script, contains('move /y "%~2" "%~3"'));
        expect(script, isNot(contains('timeout')));
        expect(script, contains('start "" "%~3"'));
        expect(script, contains('del "%~f0"'));
        expect(script, contains('tylog-update.log'));
      },
    );

    test('Windows paths use backslashes only', () {
      expect(
        windowsPath(r'C:\Users\a b\AppData\Local\Temp', 'x.exe'),
        r'C:\Users\a b\AppData\Local\Temp\x.exe',
      );
      expect(windowsPath('C:/Temp/', 'x.exe'), r'C:\Temp\x.exe');
    });

    test(
      'script waits for a running process, then swaps and relaunches',
      () async {
        final dir = Directory.systemTemp.createTempSync('tylog-upd-test-');
        addTearDown(() => dir.deleteSync(recursive: true));
        final helper = windowsPath(dir.path, 'helper.cmd');
        final fresh = windowsPath(dir.path, 'new.txt');
        final target = windowsPath(dir.path, 'target.txt');
        File(helper).writeAsStringSync(
          windowsUpdateScript()
              .replaceAll('\r\n', '\n')
              .replaceAll('\n', '\r\n'),
        );
        File(fresh).writeAsStringSync('new');
        File(target).writeAsStringSync('old');
        final running = await Process.start('ping', ['-n', '30', '127.0.0.1']);
        running.stdout.drain<void>();
        running.stderr.drain<void>();
        final helperRun = await Process.start(
          'cmd',
          ['/c', helper, '${running.pid}', fresh, target],
          environment: {
            'TEMP': dir.path,
            'TMP': dir.path,
            'TYLOG_UPDATE_NO_START': '1',
          },
        );
        helperRun.stdout.drain<void>();
        helperRun.stderr.drain<void>();
        await Future<void>.delayed(const Duration(seconds: 3));
        expect(File(target).readAsStringSync(), 'old'); // still waiting
        running.kill();
        await helperRun.exitCode.timeout(const Duration(seconds: 40));
        final log = File(windowsPath(dir.path, 'tylog-update.log'));
        expect(File(target).readAsStringSync(), 'new');
        expect(log.readAsStringSync(), isNot(contains('could not replace')));
      },
      skip: Platform.isWindows ? false : 'runs the Windows helper',
      timeout: const Timeout(Duration(minutes: 1)),
    );
  });
}
