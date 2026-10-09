import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/vault_service.dart';
import 'package:tylog/vault_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('background failure reports false to the worker', () async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => throw PlatformException(code: 'unavailable'),
    );
    MethodCall? completion;
    messenger.setMockMethodCallHandler(AndroidTreeVaultStorage.channel, (
      call,
    ) async {
      completion = call;
      return null;
    });
    addTearDown(() {
      messenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        null,
      );
      messenger.setMockMethodCallHandler(AndroidTreeVaultStorage.channel, null);
    });
    await vaultServiceMain();
    expect(completion?.method, 'backgroundDone');
    expect(completion?.arguments, false);
  });
}
