import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/vault.dart';
import 'package:tylog/vault_registry.dart';
import 'package:tylog/vault_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'a stalled SAF call surfaces as a PlatformException instead of hanging',
    () async {
      final originalTimeout = AndroidTreeVaultStorage.safCallTimeout;
      AndroidTreeVaultStorage.safCallTimeout = const Duration(milliseconds: 50);
      addTearDown(
        () => AndroidTreeVaultStorage.safCallTimeout = originalTimeout,
      );
      const channel = MethodChannel('org.tylog.tylog/saf');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            channel,
            (call) => Completer<Object?>().future,
          );
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      final storage = AndroidTreeVaultStorage(
        uri: 'content://test/tree',
        name: 'Test',
      );

      await expectLater(
        storage.exists('notes/a.typ'),
        throwsA(
          isA<PlatformException>().having(
            (error) => error.code,
            'code',
            'saf_timeout',
          ),
        ),
      );
    },
  );

  test(
    'storage contract sees external edits and preserves binary files',
    () async {
      for (final simulatedSaf in [false, true]) {
        final directory = await Directory.systemTemp.createTemp(
          'tylog_storage_',
        );
        addTearDown(() => directory.delete(recursive: true));
        final storage = simulatedSaf
            ? _SimulatedSafStorage(directory)
            : LocalVaultStorage(directory);

        await storage.createDirectory('notes');
        await storage.writeText('notes/a.typ', 'first');
        await storage.writeBytes('assets/data.bin', [0, 1, 2, 255]);
        expect(await storage.readText('notes/a.typ'), 'first');
        expect(await storage.readBytes('assets/data.bin'), [0, 1, 2, 255]);
        expect(
          (await storage.list(recursive: true)).map((entry) => entry.path),
          containsAll(['notes/a.typ', 'assets/data.bin']),
        );

        await File('${directory.path}/notes/a.typ').writeAsString('external');
        expect(await storage.readText('notes/a.typ'), 'external');
        await storage.writeText('notes/a.typ', 'atomic');
        expect(
          await File('${directory.path}/notes/a.typ.tmp').exists(),
          isFalse,
        );
      }
    },
  );

  test('concurrent overwrites are atomic and leave no temp files', () async {
    final directory = await Directory.systemTemp.createTemp('tylog_atomic_');
    addTearDown(() => directory.delete(recursive: true));
    final storage = LocalVaultStorage(directory);

    await storage.writeText('notes/a.typ', 'one');
    // Unique temp names: two in-flight writes to the same path must not
    // collide, and the target must never be deleted before the rename.
    await Future.wait([
      storage.writeText('notes/a.typ', 'two'),
      storage.writeText('notes/a.typ', 'three'),
    ]);

    expect(['two', 'three'], contains(await storage.readText('notes/a.typ')));
    final leftovers = await directory
        .list(recursive: true)
        .where((entity) => entity.path.endsWith('.tmp'))
        .toList();
    expect(leftovers, isEmpty);
  });

  test(
    'vault migration copies durable state, verifies hashes, and keeps source',
    () async {
      final sourceDir = await Directory.systemTemp.createTemp('tylog_source_');
      final destinationDir = await Directory.systemTemp.createTemp(
        'tylog_destination_',
      );
      addTearDown(() => sourceDir.delete(recursive: true));
      addTearDown(() => destinationDir.delete(recursive: true));
      final source = LocalVaultStorage(sourceDir);
      final destination = _SimulatedSafStorage(destinationDir);
      final vault = Vault.withStorage(source);
      await vault.ensureCreated();
      await source.writeText('notes/a.typ', 'keep me');
      await source.writeText('.tylog/sync_state.json', '{"cursors":{}}');
      await source.writeText('_index/index.json', 'cache');

      await copyVaultStorage(source, destination);

      expect(await destination.readText('notes/a.typ'), 'keep me');
      expect(await destination.exists('.tylog/sync_state.json'), isTrue);
      expect(await destination.exists('_index/index.json'), isFalse);
      expect(await source.readText('notes/a.typ'), 'keep me');
    },
  );

  test('failed migration does not modify the source vault', () async {
    final sourceDir = await Directory.systemTemp.createTemp('tylog_source_');
    final destinationDir = await Directory.systemTemp.createTemp(
      'tylog_destination_',
    );
    addTearDown(() => sourceDir.delete(recursive: true));
    addTearDown(() => destinationDir.delete(recursive: true));
    final source = LocalVaultStorage(sourceDir);
    final vault = Vault.withStorage(source);
    await vault.ensureCreated();
    await source.writeText('notes/a.typ', 'original');

    await expectLater(
      copyVaultStorage(source, _CorruptingStorage(destinationDir)),
      throwsStateError,
    );
    expect(await source.readText('notes/a.typ'), 'original');
  });

  test('simulated SAF storage surfaces permission loss', () async {
    final directory = await Directory.systemTemp.createTemp('tylog_revoked_');
    addTearDown(() => directory.delete(recursive: true));
    final storage = _RevocableSafStorage(directory);
    await storage.writeText('notes/a.typ', 'available');

    storage.revoke();

    await expectLater(storage.readText('notes/a.typ'), throwsStateError);
    expect(() => storage.writeText('notes/a.typ', 'blocked'), throwsStateError);
  });
}

class _SimulatedSafStorage extends LocalVaultStorage {
  _SimulatedSafStorage(super.root);

  @override
  String get location => 'content://test/${root.path.hashCode}';
}

class _CorruptingStorage extends _SimulatedSafStorage {
  _CorruptingStorage(super.root);

  @override
  Future<void> importFile(String path, File source) async {
    await super.importFile(path, source);
    await writeText(path, 'corrupt');
  }
}

class _RevocableSafStorage extends _SimulatedSafStorage {
  _RevocableSafStorage(super.root);

  bool _revoked = false;

  void revoke() => _revoked = true;

  void _checkPermission() {
    if (_revoked) throw StateError('Persisted tree permission was revoked');
  }

  @override
  Future<Uint8List> readBytes(String path) {
    _checkPermission();
    return super.readBytes(path);
  }

  @override
  Future<void> writeBytes(String path, List<int> bytes) {
    _checkPermission();
    return super.writeBytes(path, bytes);
  }
}
