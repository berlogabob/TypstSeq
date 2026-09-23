import 'package:integration_test/integration_test_driver.dart';

/// Driver for `flutter drive`, which unlike `flutter test` supports `--profile`.
///
/// That matters for one specific thing: a debug build carries
/// `applicationIdSuffix = ".debug"` (android/app/build.gradle.kts), so it installs
/// as a *different* app with no persisted SAF grant and cannot see the real vault.
/// A profile build is release-signed with no suffix, so it inherits both.
///
/// Real-vault checks need the production package; synthetic P12 performance
/// checks use `-PtylogProfileSuffix=.profiletest` for an isolated profile app.
// Performance failures still need their timeline evidence written to disk.
Future<void> main() => integrationDriver(writeResponseOnFailure: true);
