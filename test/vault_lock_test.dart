import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/vault_lock.dart';
import 'package:tylog/vault_service.dart';
import 'package:tylog_core/storage.dart';

void main() {
  test('the background budget matches the timeout the platform enforces', () {
    // The bug was never the number - it was that the lock's expiry and the
    // process's lifetime were unrelated constants in two languages. Derived
    // from the Kotlin source so it cannot drift silently, the same way
    // package_contract_test derives its check from the package.
    final kotlin = File(
      'android/app/src/main/kotlin/org/tylog/tylog/VaultSyncWorker.kt',
    ).readAsStringSync();
    final match = RegExp(
      r'TIMEOUT_MILLIS\s*=\s*([0-9]+)\s*\*\s*([0-9]+)\s*\*\s*([0-9]+)L',
    ).firstMatch(kotlin);
    expect(match, isNotNull, reason: 'TIMEOUT_MILLIS moved or changed shape');
    final millis =
        int.parse(match!.group(1)!) *
        int.parse(match.group(2)!) *
        int.parse(match.group(3)!);
    expect(
      backgroundRunBudget.inMilliseconds,
      lessThanOrEqualTo(millis),
      reason: 'the declared deadline must not outlive the process',
    );
  });

  test('a declared deadline expires without waiting for staleAfter', () async {
    final root = await Directory.systemTemp.createTemp('tylog_lock_deadline_');
    addTearDown(() => root.delete(recursive: true));
    final storage = LocalVaultStorage(root);
    await storage.createDirectory('.tylog');

    expect(
      await VaultLock.acquire(
        storage,
        'service',
        validFor: const Duration(milliseconds: 1),
      ),
      isTrue,
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(
      await VaultLock.heldByOther(storage, 'ui'),
      isFalse,
      reason: 'a holder that declared 1ms must not block for ten minutes',
    );
  });

  test('a declared deadline still blocks before it elapses', () async {
    final root = await Directory.systemTemp.createTemp('tylog_lock_holds_');
    addTearDown(() => root.delete(recursive: true));
    final storage = LocalVaultStorage(root);
    await storage.createDirectory('.tylog');

    await VaultLock.acquire(
      storage,
      'service',
      validFor: const Duration(minutes: 5),
    );

    expect(await VaultLock.heldByOther(storage, 'ui'), isTrue);
    expect(await VaultLock.acquire(storage, 'ui'), isFalse);
  });

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
