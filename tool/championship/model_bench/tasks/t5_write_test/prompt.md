Create ONE new file, test/macos_no_sandbox_test.dart. Do not modify or create any other file.

Project rule: the macOS app is distributed directly, so the App Sandbox must stay OFF. Both macos/Runner/Release.entitlements and macos/Runner/DebugProfile.entitlements must contain the key `com.apple.security.app-sandbox` followed by `<false/>`.

Write a `flutter_test` test that guards this rule: it passes on the current files and fails if EITHER file sets that key to `<true/>` or drops the key. Other keys in those files may be `<true/>`; the test must look at the value that follows the sandbox key, not at the file as a whole. Tests run with the project root as the working directory.

`flutter test test/macos_no_sandbox_test.dart` must pass.
