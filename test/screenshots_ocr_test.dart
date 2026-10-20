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

  test(
    'installedScreenshotMode reports off when no agents exist',
    () async {
      final home = await homeDir('off').create(recursive: true);
      addTearDown(() => home.delete(recursive: true));
      expect(await installedScreenshotMode(home: home.path), 'off');
    },
  );

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
}
