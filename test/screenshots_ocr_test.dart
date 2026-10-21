import 'dart:io';

import 'package:tylog/screenshots_ocr.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'plist records StandardOutPath/StandardErrorPath with the label log',
    () {
      final plist = screenshotLaunchAgentPlist(
        home: '/home/runner',
        vault: '/vault',
        mode: 'watch',
        label: 'org.tylog.screenshots',
      );
      expect(
        plist,
        contains(
          '<key>StandardOutPath</key>'
          '<string>/home/runner/Nextcloud/InstantUpload/Screenshots/'
          'org.tylog.screenshots.log</string>',
        ),
      );
      expect(
        plist,
        contains(
          '<key>StandardErrorPath</key>'
          '<string>/home/runner/Nextcloud/InstantUpload/Screenshots/'
          'org.tylog.screenshots.log</string>',
        ),
      );
    },
  );

  Directory homeDir(String name) => Directory(
    '${Directory.systemTemp.path}/screenshots-ocr-$name-'
    '${DateTime.now().microsecondsSinceEpoch}',
  );

  Future<void> writeAgent(Directory home, String name, String content) async {
    final dir = Directory('${home.path}/Library/LaunchAgents');
    await dir.create(recursive: true);
    await File('${dir.path}/$name').writeAsString(content);
  }

  test('installedScreenshotMode reports off when no agents exist', () async {
    final home = await homeDir('off').create(recursive: true);
    addTearDown(() => home.delete(recursive: true));
    expect(await installedScreenshotMode(home: home.path), 'off');
  });

  test(
    'installedScreenshotMode reports watch for a lone ollama agent',
    () async {
      final home = await homeDir('watch').create(recursive: true);
      addTearDown(() => home.delete(recursive: true));
      await writeAgent(
        home,
        'org.tylog.screenshots.plist',
        'ollama_ocr.py --watch',
      );
      expect(await installedScreenshotMode(home: home.path), 'watch');
    },
  );

  test(
    'installedScreenshotMode reports both when agents are present',
    () async {
      final home = await homeDir('both').create(recursive: true);
      addTearDown(() => home.delete(recursive: true));
      await writeAgent(
        home,
        'org.tylog.screenshots.plist',
        'ollama_ocr.py --watch',
      );
      await writeAgent(
        home,
        'org.tylog.screenshots.schedule.plist',
        'backfill.py',
      );
      expect(await installedScreenshotMode(home: home.path), 'both');
    },
  );

  test('screenshotHealthLine reports current, behind, and invalid health', () {
    expect(
      screenshotHealthLine({'checked_at': '12:34', 'ok': true}),
      'Screenshots up to date (checked 12:34)',
    );
    expect(
      screenshotHealthLine({
        'checked_at': '12:34',
        'ok': false,
        'lag_hours': 2.6,
        'newest_upload': '2026-10-20',
      }),
      'Screenshots behind by 3 h, newest upload 2026-10-20',
    );
    expect(screenshotHealthLine(null), isNull);
  });

  test('plist uses the chosen scripts folder and uv path', () {
    final plist = screenshotLaunchAgentPlist(
      home: '/Users/u',
      vault: '/v',
      mode: 'watch',
      scriptsDir: '/x/Shots',
      uvPath: '/u/bin/uv',
    );
    expect(plist, contains('<string>/x/Shots</string>'));
    expect(plist, contains('/x/Shots/org.tylog.screenshots.log'));
    expect(plist, contains('<string>/u/bin/uv</string>'));
    expect(plist, isNot(contains('Nextcloud')));
  });

  test('findUv finds uv under the home folder', () async {
    final home = await Directory.systemTemp.createTemp('uv-home-');
    addTearDown(() => home.delete(recursive: true));
    await File('${home.path}/.local/bin/uv').create(recursive: true);
    expect(
      await findUv(home: home.path, system: const []),
      '${home.path}/.local/bin/uv',
    );
    expect(await findUv(home: '/nonexistent', system: const []), isNull);
  });

  test('missing scripts folder gives a health line, not an error', () async {
    final dir = await Directory.systemTemp.createTemp('shots-');
    addTearDown(() => dir.delete(recursive: true));
    expect(
      screenshotScriptsHealth(dir.path),
      'Screenshot scripts not found in ${dir.path}',
    );
    await File('${dir.path}/ollama_ocr.py').create();
    expect(screenshotScriptsHealth(dir.path), isNull);
  });

  test('the Mac applies the wanted screenshot mode only when it differs', () {
    expect(screenshotsNeedApply('watch', '03:00', 'off', '03:00'), isTrue);
    expect(
      screenshotsNeedApply('schedule', '04:00', 'schedule', '03:00'),
      isTrue,
    );
    expect(screenshotsNeedApply('watch', '03:00', 'watch', '03:00'), isFalse);
    // Nothing wanted yet (older vaults): keep what the Mac has.
    expect(screenshotsNeedApply(null, null, 'both', '03:00'), isFalse);
    expect(screenshotsNeedApply('bogus', '03:00', 'off', '03:00'), isFalse);
  });

  test('a Mac publishes the mode it runs when none is wanted yet', () {
    expect(screenshotsToPublish(null, 'both', '03:00'), ('both', '03:00'));
    expect(screenshotsToPublish('watch', 'both', '03:00'), isNull);
    expect(screenshotsToPublish(null, 'nonsense', '03:00'), isNull);
  });

  test(
    'agents survive launchctl reporting error 5 or a slow bootout',
    () async {
      final home = await Directory.systemTemp.createTemp('agents-home-');
      addTearDown(() => home.delete(recursive: true));
      await File('${home.path}/.local/bin/uv').create(recursive: true);
      final calls = <String>[];
      var printsUntilLoaded = 2;
      Future<ProcessResult> run(String exe, List<String> args) async {
        calls.add('${exe.split('/').last} ${args.first}');
        if (exe.endsWith('id')) return ProcessResult(0, 0, '501', '');
        if (args.first == 'bootstrap') {
          // Error 5, as launchctl reports while the agent still loads.
          return ProcessResult(0, 5, '', 'Bootstrap failed: 5');
        }
        if (args.first == 'print') {
          return ProcessResult(0, printsUntilLoaded-- > 0 ? 113 : 0, '', '');
        }
        return ProcessResult(0, 0, '', '');
      }

      await configureScreenshotsOcr(
        '/vault',
        'both',
        '03:00',
        home: home.path,
        run: run,
        retryDelay: Duration.zero,
      );
      for (final label in [
        'org.tylog.screenshots',
        'org.tylog.screenshots.schedule',
      ]) {
        expect(
          File('${home.path}/Library/LaunchAgents/$label.plist').existsSync(),
          isTrue,
          reason: label,
        );
      }
      expect(
        calls.where((c) => c == 'launchctl bootstrap').length,
        greaterThan(2),
      );
    },
    skip: Platform.isMacOS ? false : 'LaunchAgents exist only on macOS',
  );
}
