import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/vault.dart';
import 'package:tylog/vault_registry.dart';
import 'package:tylog/vault_storage.dart';
import 'package:tylog/platform_file_actions.dart';
import 'support/temp_dir.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('SAF note imports validate the exact bytes sent to storage', () async {
    final dir = await Directory.systemTemp.createTemp('tylog_import_guard_');
    addTearDown(() => deleteTempDir(dir));
    final source = File('${dir.path}/source.typ');
    final calls = <MethodCall>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(AndroidTreeVaultStorage.channel, (
      call,
    ) async {
      calls.add(call);
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(
        AndroidTreeVaultStorage.channel,
        null,
      ),
    );
    final storage = AndroidTreeVaultStorage(
      uri: 'content://test/tree',
      name: 'Test',
    );
    await source.writeAsString('{"revision":{},"node":{}}');
    await expectLater(
      importPlatformFile(storage, 'notes/a.typ', source),
      throwsFormatException,
    );
    expect(calls, isEmpty);
    await source.writeAsString('Headerless legacy note');
    await importPlatformFile(storage, 'notes/a.typ', source);
    final write = calls.singleWhere(
      (call) =>
          call.method == 'write' && call.arguments['path'] == 'notes/a.typ',
    );
    expect(
      utf8.decode(write.arguments['bytes'] as List<int>),
      'Headerless legacy note',
    );
    calls.clear();
    await importPlatformFile(storage, 'assets/a.bin', source);
    expect(calls.single.method, 'import');
  });

  test(
    'revision JSON cannot replace a daily note through local or SAF storage',
    () async {
      final dir = await Directory.systemTemp.createTemp('tylog_guard_');
      addTearDown(() => deleteTempDir(dir));
      final local = LocalVaultStorage(dir);
      const path = 'daily/2026/11/2026-11-02.typ';
      const note = '#import "/_system/tylog.typ" as tylog\n\nExisting note';
      const revision =
          '{"revision":{"id":"note-1"},"history":[],"node":{"content":"Existing note"}}';
      await local.writeText(path, note);
      await expectLater(local.writeText(path, revision), throwsFormatException);
      expect(await local.readText(path), note);
      await local.writeText('_system/revisions/note-1.json', revision);

      final calls = <MethodCall>[];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(AndroidTreeVaultStorage.channel, (
        call,
      ) async {
        calls.add(call);
        return null;
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(
          AndroidTreeVaultStorage.channel,
          null,
        ),
      );
      final saf = AndroidTreeVaultStorage(
        uri: 'content://test/tree',
        name: 'Test',
      );
      await expectLater(saf.writeText(path, revision), throwsFormatException);
      expect(calls, isEmpty);
    },
  );

  test(
    'note writes and appends reject invalid UTF-8 and preserve legacy text',
    () async {
      final dir = await Directory.systemTemp.createTemp('tylog_guard_extra_');
      addTearDown(() => deleteTempDir(dir));
      final storage = LocalVaultStorage(dir);
      const path = 'notes/legacy.typ';
      const legacy = 'A headerless legacy note with {braces}.\n';
      await storage.writeText(path, legacy);
      await expectLater(storage.writeBytes(path, [255]), throwsFormatException);
      expect(await storage.readText(path), legacy);
      const other = 'notes/append.typ';
      await expectLater(
        storage.appendBytes(other, [255]),
        throwsFormatException,
      );
      expect(await storage.exists(other), isFalse);
      await storage.writeText(other, '{"legacy": true}');
      expect(await storage.readText(other), '{"legacy": true}');
      await storage.appendBytes(path, utf8.encode('More text.\n'));
      expect(
        await storage.readText(path),
        '$legacy'
        'More text.\n',
      );
    },
  );

  test('SAF append validates note bytes before sending the append', () async {
    final calls = <String>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(AndroidTreeVaultStorage.channel, (
      call,
    ) async {
      calls.add(call.method);
      if (call.method == 'exists') return false;
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(
        AndroidTreeVaultStorage.channel,
        null,
      ),
    );
    final storage = AndroidTreeVaultStorage(
      uri: 'content://test/tree',
      name: 'Test',
    );
    await expectLater(
      storage.appendBytes('notes/a.typ', [255]),
      throwsFormatException,
    );
    expect(calls, ['exists']);
  });

  test(
    'concurrent SAF appends survive a provider without append mode',
    () async {
      var content = 'start\n';
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(AndroidTreeVaultStorage.channel, (
        call,
      ) async {
        switch (call.method) {
          case 'append':
            throw PlatformException(code: 'unsupported');
          case 'exists':
            return true;
          case 'read':
            final snapshot = content;
            await Future<void>.delayed(const Duration(milliseconds: 20));
            return Uint8List.fromList(utf8.encode(snapshot));
          case 'write':
            content = utf8.decode(
              (call.arguments as Map)['bytes'] as Uint8List,
            );
            return null;
        }
        return null;
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(
          AndroidTreeVaultStorage.channel,
          null,
        ),
      );
      final first = AndroidTreeVaultStorage(
        uri: 'content://test/tree',
        name: 'Test',
      );
      final second = AndroidTreeVaultStorage(
        uri: 'content://test/tree',
        name: 'Test',
      );
      await Future.wait([
        first.appendBytes('logs/events.jsonl', utf8.encode('one\n')),
        second.appendBytes('logs/events.jsonl', utf8.encode('two\n')),
      ]);
      expect(content, 'start\none\ntwo\n');
    },
  );

  test('a later SAF append waits for a timed-out provider call', () async {
    final originalTimeout = AndroidTreeVaultStorage.safCallTimeout;
    AndroidTreeVaultStorage.safCallTimeout = const Duration(milliseconds: 50);
    addTearDown(() => AndroidTreeVaultStorage.safCallTimeout = originalTimeout);
    final pending = Completer<Object?>();
    var calls = 0;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(AndroidTreeVaultStorage.channel, (call) {
      if (call.method == 'append') {
        calls++;
        return calls == 1 ? pending.future : Future.value(null);
      }
      return Future.value(null);
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(
        AndroidTreeVaultStorage.channel,
        null,
      ),
    );
    final storage = AndroidTreeVaultStorage(
      uri: 'content://test/timeout-queue',
      name: 'Test',
    );
    const path = 'logs/events.jsonl';
    await expectLater(
      storage.appendBytes(path, utf8.encode('one\n')),
      throwsA(isA<PlatformException>()),
    );
    final second = storage.appendBytes(path, utf8.encode('two\n'));
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(calls, 1);
    pending.complete();
    await second;
    expect(calls, 2);
  });

  test('late successful note append commits its index marker', () async {
    final originalTimeout = AndroidTreeVaultStorage.safCallTimeout;
    AndroidTreeVaultStorage.safCallTimeout = const Duration(milliseconds: 50);
    addTearDown(() => AndroidTreeVaultStorage.safCallTimeout = originalTimeout);
    final pending = Completer<Object?>();
    final committed = Completer<void>();
    final markers = <Map<String, dynamic>>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(AndroidTreeVaultStorage.channel, (
      call,
    ) async {
      if (call.method == 'exists') return false;
      if (call.method == 'append') return pending.future;
      if (call.method == 'write') {
        final value =
            jsonDecode(utf8.decode(call.arguments['bytes'] as Uint8List))
                as Map<String, dynamic>;
        markers.add(value);
        if (value.containsKey('committedAt')) committed.complete();
      }
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(
        AndroidTreeVaultStorage.channel,
        null,
      ),
    );
    final storage = AndroidTreeVaultStorage(
      uri: 'content://test/late',
      name: 'Test',
    );
    await expectLater(
      storage.appendBytes('notes/a.typ', utf8.encode('hello')),
      throwsA(isA<PlatformException>()),
    );
    expect(markers.single, {'path': 'notes/a.typ'});
    pending.complete();
    await committed.future.timeout(const Duration(seconds: 1));
    expect(markers.last['path'], 'notes/a.typ');
  });

  test('a timed-out SAF fallback write keeps later appends queued', () async {
    final originalTimeout = AndroidTreeVaultStorage.safCallTimeout;
    AndroidTreeVaultStorage.safCallTimeout = const Duration(milliseconds: 50);
    addTearDown(() => AndroidTreeVaultStorage.safCallTimeout = originalTimeout);
    final pending = Completer<Object?>();
    var content = 'start\n';
    var writes = 0;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(AndroidTreeVaultStorage.channel, (
      call,
    ) async {
      switch (call.method) {
        case 'append':
          throw PlatformException(code: 'unsupported');
        case 'exists':
          return true;
        case 'read':
          return Uint8List.fromList(utf8.encode(content));
        case 'write':
          writes++;
          final next = utf8.decode(call.arguments['bytes'] as Uint8List);
          if (writes == 1) await pending.future;
          content = next;
          return null;
      }
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(
        AndroidTreeVaultStorage.channel,
        null,
      ),
    );
    final storage = AndroidTreeVaultStorage(
      uri: 'content://test/fallback-timeout',
      name: 'Test',
    );
    const path = 'logs/events.jsonl';
    await expectLater(
      storage.appendBytes(path, utf8.encode('one\n')),
      throwsA(
        isA<PlatformException>().having((e) => e.code, 'code', 'saf_timeout'),
      ),
    );
    final second = storage.appendBytes(path, utf8.encode('two\n'));
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(writes, 1);
    pending.complete();
    await second;
    expect(content, 'start\none\ntwo\n');
  });

  test('vault paths reject aliases and control characters', () {
    for (final path in ['assets/./a.bin', 'assets/../a.bin', 'assets/a\nbin']) {
      expect(() => validateVaultPath(path), throwsArgumentError);
    }
    expect(validateVaultPath('assets/a.bin'), 'assets/a.bin');
  });

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
    'a timed-out SAF append does not retry an operation still in flight',
    () async {
      final originalTimeout = AndroidTreeVaultStorage.safCallTimeout;
      AndroidTreeVaultStorage.safCallTimeout = const Duration(milliseconds: 50);
      addTearDown(
        () => AndroidTreeVaultStorage.safCallTimeout = originalTimeout,
      );
      final calls = <String>[];
      final pending = Completer<Object?>();
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(AndroidTreeVaultStorage.channel, (
        call,
      ) {
        calls.add(call.method);
        return call.method == 'append' ? pending.future : Future.value(null);
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(
          AndroidTreeVaultStorage.channel,
          null,
        ),
      );

      final storage = AndroidTreeVaultStorage(
        uri: 'content://test/tree',
        name: 'Test',
      );
      await expectLater(
        storage.appendBytes('logs/events.jsonl', utf8.encode('row\n')),
        throwsA(
          isA<PlatformException>().having((e) => e.code, 'code', 'saf_timeout'),
        ),
      );
      expect(calls, ['append']);
      pending.complete();
    },
  );

  test(
    'storage contract sees external edits and preserves binary files',
    () async {
      for (final simulatedSaf in [false, true]) {
        final directory = await Directory.systemTemp.createTemp(
          'tylog_storage_',
        );
        addTearDown(() => deleteTempDir(directory));
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

  test('concurrent local appends preserve both complete lines', () async {
    final directory = await Directory.systemTemp.createTemp('tylog_append_');
    addTearDown(() => deleteTempDir(directory));
    final storage = LocalVaultStorage(directory);
    await Future.wait([
      storage.appendBytes('logs/events.jsonl', utf8.encode('one\n')),
      storage.appendBytes('logs/events.jsonl', utf8.encode('two\n')),
    ]);
    expect(
      (await storage.readText('logs/events.jsonl')).split('\n'),
      anyOf(equals(['one', 'two', '']), equals(['two', 'one', ''])),
    );
  });

  test(
    'composite append routes writes and respects mount permissions',
    () async {
      final main = await Directory.systemTemp.createTemp('tylog_main_');
      final mount = await Directory.systemTemp.createTemp('tylog_mount_');
      addTearDown(() async {
        await main.delete(recursive: true);
        await mount.delete(recursive: true);
      });
      final storage = CompositeVaultStorage(
        LocalVaultStorage(main),
        {'archive': LocalVaultStorage(mount)},
        writableMounts: {'archive'},
      );
      await storage.appendBytes('ext/archive/a.jsonl', utf8.encode('row\n'));
      expect(await File('${mount.path}/a.jsonl').readAsString(), 'row\n');
      storage.writableMounts.clear();
      await expectLater(
        storage.appendBytes('ext/archive/a.jsonl', [1]),
        throwsUnsupportedError,
      );
    },
  );

  test('SAF append uses the append channel', () async {
    final calls = <MethodCall>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(AndroidTreeVaultStorage.channel, (
      call,
    ) async {
      calls.add(call);
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(
        AndroidTreeVaultStorage.channel,
        null,
      ),
    );
    final storage = AndroidTreeVaultStorage(
      uri: 'content://test/tree',
      name: 'Test',
    );
    await storage.appendBytes(
      '_system/decisions/a.jsonl',
      utf8.encode('row\n'),
    );
    expect(calls.single.method, 'append');
    expect(calls.single.arguments['bytes'], utf8.encode('row\n'));
  });

  test('concurrent overwrites are atomic and leave no temp files', () async {
    final directory = await Directory.systemTemp.createTemp('tylog_atomic_');
    addTearDown(() => deleteTempDir(directory));
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
      addTearDown(() => deleteTempDir(sourceDir));
      addTearDown(() => deleteTempDir(destinationDir));
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
    addTearDown(() => deleteTempDir(sourceDir));
    addTearDown(() => deleteTempDir(destinationDir));
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
    addTearDown(() => deleteTempDir(directory));
    final storage = _RevocableSafStorage(directory);
    await storage.writeText('notes/a.typ', 'available');

    storage.revoke();

    await expectLater(storage.readText('notes/a.typ'), throwsStateError);
    expect(() => storage.writeText('notes/a.typ', 'blocked'), throwsStateError);
  });
}

class _SimulatedSafStorage extends LocalVaultStorage {
  _SimulatedSafStorage(super.root);
}

class _CorruptingStorage extends _SimulatedSafStorage {
  _CorruptingStorage(super.root);

  @override
  Future<void> writeBytes(String path, List<int> bytes) async {
    await super.writeBytes(path, bytes);
    await super.writeBytes(path, utf8.encode('corrupt'));
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
