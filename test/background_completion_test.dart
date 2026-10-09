import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/vault_service.dart';
import 'package:tylog/vault_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'headless unconfigured vault completes without initialization writes',
    () async {
      final root = await Directory('.dart_tool').createTemp('headless-');
      addTearDown(() => root.delete(recursive: true));
      final registry = File('${root.path}/vaults.json');
      final original = jsonEncode({
        'vaults': [
          {
            'id': 'fixture',
            'name': 'Fixture',
            'storage': {'kind': 'local-path', 'path': '${root.path}/vault'},
          },
        ],
        'active': 'fixture',
        'deviceId': 'fixture-device',
      });
      await registry.writeAsString(original);
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      const paths = MethodChannel('plugins.flutter.io/path_provider');
      messenger.setMockMethodCallHandler(paths, (_) async => root.path);
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(AndroidTreeVaultStorage.channel, (
        call,
      ) async {
        calls.add(call);
        return null;
      });
      addTearDown(() {
        messenger.setMockMethodCallHandler(paths, null);
        messenger.setMockMethodCallHandler(
          AndroidTreeVaultStorage.channel,
          null,
        );
      });
      await vaultServiceMain().timeout(const Duration(seconds: 2));
      expect(calls.map((c) => c.method), ['backgroundDone']);
      expect(calls.single.arguments, true);
      expect(await registry.readAsString(), original);
      expect(root.listSync().map((f) => f.path), [registry.path]);
    },
  );

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
