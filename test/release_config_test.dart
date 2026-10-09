import 'dart:io';

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
    final assertion = File('tool/assert_source_built.sh').readAsStringSync();
    expect(assertion, contains('grep -qx "\$platform" "\$stamp"'));
    expect(assertion, isNot(contains('armeabi-v7a')));
  });
}
