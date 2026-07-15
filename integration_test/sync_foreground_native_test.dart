import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tylog/vault_storage.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Android foreground sync service starts, updates, and stops', (
    tester,
  ) async {
    if (!Platform.isAndroid) return;
    const holdSeconds = int.fromEnvironment('TYLOG_FOREGROUND_HOLD_SECONDS');

    await AndroidTreeVaultStorage.startSyncForeground(
      detail: '1/2 · notes/first.typ',
    );
    await AndroidTreeVaultStorage.updateSyncForeground(
      detail: '2/2 · notes/second.typ',
    );
    if (holdSeconds > 0) {
      await Future<void>.delayed(Duration(seconds: holdSeconds));
    }
    await AndroidTreeVaultStorage.stopSyncForeground();
  });
}
