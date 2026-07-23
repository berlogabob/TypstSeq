import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/desktop_updater.dart';

String _release({
  required String tag,
  bool withMacAsset = true,
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
}
