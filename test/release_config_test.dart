import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
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
