import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('macOS stays unsandboxed until persistent bookmarks are supported', () {
    for (final name in ['Release', 'DebugProfile']) {
      final plist = File('macos/Runner/$name.entitlements').readAsStringSync();
      final sandbox = RegExp(
        r'<key>com\.apple\.security\.app-sandbox</key>\s*<(true|false)\s*/>',
      ).allMatches(plist).toList();
      expect(sandbox, hasLength(1), reason: name);
      expect(sandbox.single.group(1), 'false', reason: name);
    }
  });

  test('packaged APK must contain the exact source-built ARM64 library', () async {
    final root = await Directory('.dart_tool').createTemp('packaged-native-');
    addTearDown(() => root.delete(recursive: true));
    final script = File('${root.path}/tool/assert_source_built.sh');
    await script.create(recursive: true);
    await script.writeAsString(
      File('tool/assert_source_built.sh').readAsStringSync(),
    );
    final native = File(
      '${root.path}/packages/typst_flutter/.typst_flutter_prebuilt/android/arm64-v8a/libtypst_flutter.so',
    );
    await native.create(recursive: true);
    await native.writeAsBytes([1, 2, 3]);
    await File(
      '${root.path}/packages/typst_flutter/.typst_flutter_prebuilt/.source-built',
    ).writeAsString('android\n');
    final apk = File('${root.path}/fixture.apk');
    for (final payload in [
      <int>[1, 2, 3],
      <int>[9, 8, 7],
      <int>[],
    ]) {
      final archive = Archive();
      if (payload.isNotEmpty) {
        archive.addFile(
          ArchiveFile(
            'lib/arm64-v8a/libtypst_flutter.so',
            payload.length,
            payload,
          ),
        );
      }
      await apk.writeAsBytes(ZipEncoder().encode(archive));
      final result = await Process.run('sh', [
        script.path,
        'android',
        '--apk',
        apk.path,
      ]);
      expect(
        result.exitCode,
        payload.isNotEmpty && payload.first == 1 ? 0 : 1,
        reason: '${result.stdout}\n${result.stderr}',
      );
    }
  });

  test('Android keeps headless Room and the Dart entrypoint reachable', () {
    expect(
      File('android/app/proguard-rules.pro').readAsStringSync(),
      contains(
        '-keep class * extends androidx.room.RoomDatabase { <init>(); }',
      ),
    );
    expect(
      File('lib/main.dart').readAsStringSync(),
      contains("import 'vault_service.dart';"),
    );
    expect(
      File('lib/vault_service.dart').readAsStringSync(),
      contains("@pragma('vm:entry-point')\nFuture<void> vaultServiceMain()"),
    );
  });

  test('debug is isolated and profile uses optional release signing', () {
    final gradle = File('android/app/build.gradle.kts').readAsStringSync();
    final debug = gradle.substring(
      gradle.indexOf('        debug {'),
      gradle.indexOf('        release {'),
    );
    final profile = gradle.substring(
      gradle.indexOf('        getByName("profile") {'),
      gradle.indexOf('\ndependencies {'),
    );
    expect(debug, contains('?: ".debug"'));
    expect(debug, contains('tylogDebugSuffix'));
    expect(
      profile,
      contains(
        'if (keystorePropertiesFile.exists()) {\n                signingConfig = signingConfigs.getByName("release")',
      ),
    );
    expect(profile, contains('tylogProfileSuffix'));
    expect(profile, contains('?.let { applicationIdSuffix = it }'));
    expect(profile, isNot(contains('".debug"')));
    expect(profile, isNot(contains('".profiletest"')));
  });

  test('release builds ARM64 and refreshes the indexer only on macOS', () {
    final makefile = File('Makefile').readAsStringSync();
    final workflow = File('.github/workflows/release.yml').readAsStringSync();
    for (final source in [makefile, workflow]) {
      final builds = RegExp(
        r'flutter build apk --release[^\n]*',
      ).allMatches(source);
      expect(builds, isNotEmpty);
      for (final build in builds) {
        expect(build.group(0), contains('--target-platform android-arm64'));
      }
    }
    expect(makefile, contains('install-indexer:\n'));
    expect(
      makefile,
      contains(
        'cd packages/tylog_core && dart compile exe bin/tylog.dart -o "\$(HOME)/.local/bin/tylog"',
      ),
    );
    expect(
      makefile,
      contains('rsync -a --delete typst/ "\$(HOME)/.local/share/tylog/typst/"'),
    );
    expect(
      makefile,
      contains(
        'launchctl kickstart -k gui/\$\$(id -u)/org.tylog.indexer || true',
      ),
    );
    expect(
      makefile,
      contains(
        '\$(MAKE) build-android\n\t@if [ "\$\$(uname -s)" = Darwin ]; then \$(MAKE) install-indexer; fi',
      ),
    );
    expect(
      workflow,
      contains(
        'flutter build apk --release --target-platform android-arm64\n'
        '      - run: ./tool/assert_source_built.sh android --apk build/app/outputs/flutter-apk/app-release.apk',
      ),
    );
    final assertion = File('tool/assert_source_built.sh').readAsStringSync();
    expect(assertion, contains('grep -qx "\$platform" "\$stamp"'));
    expect(assertion, isNot(contains('armeabi-v7a')));
  });
}
