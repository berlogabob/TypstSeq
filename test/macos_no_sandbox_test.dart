import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('macOS entitlements should not have sandbox enabled', () {
    // Read Release.entitlements
    final releaseEntitlements = File('macos/Runner/Release.entitlements');
    expect(releaseEntitlements.existsSync(), true);
    final releaseContent = releaseEntitlements.readAsStringSync();
    expect(releaseContent, contains('com.apple.security.app-sandbox'));
    expect(releaseContent, contains('<false/>'));

    // Read DebugProfile.entitlements
    final debugProfileEntitlements = File(
      'macos/Runner/DebugProfile.entitlements',
    );
    expect(debugProfileEntitlements.existsSync(), true);
    final debugProfileContent = debugProfileEntitlements.readAsStringSync();
    expect(debugProfileContent, contains('com.apple.security.app-sandbox'));
    expect(debugProfileContent, contains('<false/>'));

    // Verify that sandbox is disabled in both files
    // The pattern should be: <key>com.apple.security.app-sandbox</key><false/>
    // Check that the key is followed by <false/> (no space or other content)
    expect(
      releaseContent,
      matches(
        RegExp(r'<key>com\.apple\.security\.app-sandbox</key>\s*<false/>'),
      ),
    );
    expect(
      debugProfileContent,
      matches(
        RegExp(r'<key>com\.apple\.security\.app-sandbox</key>\s*<false/>'),
      ),
    );
  });
}
