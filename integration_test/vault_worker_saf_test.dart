import 'dart:io';
import 'dart:isolate';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tylog/vault_storage.dart';

/// The one Phase-1 assumption with no desktop equivalent.
///
/// On Android the vault lives behind the Storage Access Framework, and every
/// read goes over the `org.tylog.tylog/saf` `MethodChannel` into `SafBridge.kt`.
/// A `MethodChannel` is bound to the isolate that created it, so the worker can
/// only reach SafBridge via `BackgroundIsolateBinaryMessenger.ensureInitialized`
/// — and if that did not work, the whole worker design would be desktop-only and
/// the phone (the thing that actually stutters) would gain nothing.
///
/// This probes the *mechanism* rather than a real vault: no granted tree is
/// needed, because what distinguishes success from failure is only whether
/// Kotlin answered at all. A reply — `false`, or a `PlatformException` carrying a
/// SAF error code — means the channel round-tripped. A missing binary messenger
/// fails differently and loudly, before any SAF logic runs.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('SafBridge answers a background isolate', (_) async {
    final token = RootIsolateToken.instance;
    expect(token, isNotNull, reason: 'no root isolate token to hand the worker');

    final outcome = await Isolate.run(() async {
      BackgroundIsolateBinaryMessenger.ensureInitialized(token!);
      final storage = AndroidTreeVaultStorage(
        uri:
            'content://com.android.externalstorage.documents/tree/'
            'primary%3ANoSuchVaultWasEverGranted',
        name: 'saf-probe',
      );
      try {
        return 'answered: hasAccess=${await storage.hasAccess()}';
      } on PlatformException catch (error) {
        return 'answered: PlatformException(${error.code})';
      } catch (error) {
        return 'unreachable: ${error.runtimeType}: $error';
      }
    });

    // ignore: avoid_print
    print('SAF-PROBE $outcome');
    expect(
      outcome,
      startsWith('answered'),
      reason:
          'the worker isolate could not reach SafBridge, so indexing an Android '
          'vault off the root isolate is impossible as designed',
    );
  }, skip: !Platform.isAndroid);
}
