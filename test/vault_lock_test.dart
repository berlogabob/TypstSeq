import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/vault_lock.dart';
import 'package:tylog_core/storage.dart';

void main() {
  late Directory dir;
  late LocalVaultStorage storage;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('tylog_vault_lock_');
    storage = LocalVaultStorage(dir);
  });

  tearDown(() => dir.delete(recursive: true));

  test('acquire, block the other owner, release, acquire again', () async {
    expect(await VaultLock.acquire(storage, 'ui'), isTrue);
    expect(await VaultLock.acquire(storage, 'service'), isFalse);
    expect(await VaultLock.heldByOther(storage, 'service'), isTrue);
    expect(await VaultLock.heldByOther(storage, 'ui'), isFalse);

    await VaultLock.release(storage, 'ui');
    expect(await VaultLock.acquire(storage, 'service'), isTrue);
  });

  test('re-acquiring one\'s own lock refreshes it', () async {
    expect(await VaultLock.acquire(storage, 'ui'), isTrue);
    expect(await VaultLock.acquire(storage, 'ui'), isTrue);
  });

  test('a stale lock is stolen', () async {
    await storage.writeBytes(
      VaultLock.path,
      utf8.encode(
        jsonEncode({
          'owner': 'service',
          'millis': DateTime.now()
              .subtract(VaultLock.staleAfter + const Duration(minutes: 1))
              .millisecondsSinceEpoch,
        }),
      ),
    );
    expect(await VaultLock.heldByOther(storage, 'ui'), isFalse);
    expect(await VaultLock.acquire(storage, 'ui'), isTrue);
  });

  test('release never removes someone else\'s lock', () async {
    expect(await VaultLock.acquire(storage, 'service'), isTrue);
    await VaultLock.release(storage, 'ui');
    expect(await VaultLock.heldByOther(storage, 'ui'), isTrue);
  });

  test('a corrupt lock file counts as no lock', () async {
    await storage.writeBytes(VaultLock.path, utf8.encode('not json'));
    expect(await VaultLock.acquire(storage, 'ui'), isTrue);
  });
}
