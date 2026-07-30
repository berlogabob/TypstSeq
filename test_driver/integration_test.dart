import 'package:integration_test/integration_test_driver.dart';

/// Driver for `flutter drive`, which unlike `flutter test` supports `--profile`.
///
/// That matters for one specific thing: a debug build carries
/// `applicationIdSuffix = ".debug"` (android/app/build.gradle.kts), so it installs
/// as a *different* app with no persisted SAF grant and cannot see the real vault.
/// A profile build is release-signed with no suffix, so it inherits both.
///
/// Only `integration_test/vault_worker_real_vault_test.dart` needs this; the rest
/// run fine under `flutter test -d <device>` because they build their own fixtures.
Future<void> main() => integrationDriver();
