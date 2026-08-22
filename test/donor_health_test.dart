import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/nextcloud_sync.dart';
import 'package:tylog/vault.dart';
import 'package:tylog_core/storage.dart';

/// A device that stops sharing its index makes every peer rebuild the whole
/// vault from scratch. The store has recorded that failure since it stopped
/// being swallowed, and nothing read the field — the channel ended in a
/// variable.
class _RefusingDonorStorage extends LocalVaultStorage {
  _RefusingDonorStorage(super.root);

  @override
  Future<void> writeText(String path, String contents) async {
    if (path.startsWith('_system/index/')) {
      throw const FileSystemException('read-only');
    }
    return super.writeText(path, contents);
  }
}

void main() {
  test('a donor publish failure reaches the vault', () async {
    final root = await Directory.systemTemp.createTemp('tylog_donor_health_');
    addTearDown(() => root.delete(recursive: true));
    final vault = Vault.withStorage(_RefusingDonorStorage(root));
    await vault.ensureCreated();

    await vault.rebuildIndex(deviceId: 'this-device');

    expect(
      vault.donorPublishError,
      isNotNull,
      reason: 'the app must be able to say the fleet is not being fed',
    );
  });

  test('a successful publish leaves no error behind', () async {
    final root = await Directory.systemTemp.createTemp('tylog_donor_ok_');
    addTearDown(() => root.delete(recursive: true));
    final vault = Vault(root);
    await vault.ensureCreated();

    await vault.rebuildIndex(deviceId: 'this-device');

    expect(vault.donorPublishError, isNull);
  });

  test('the trace writer is reachable without a cloud config', () async {
    // Indexing happens whether or not sync is configured, and a device that
    // cannot sync at all is exactly where donor health matters most.
    final root = await Directory.systemTemp.createTemp('tylog_trace_');
    addTearDown(() => root.delete(recursive: true));
    final vault = Vault(root);
    await vault.ensureCreated();

    await appendVaultTrace(vault, [
      {'event': 'indexed', 'notes': 3},
    ]);

    expect(
      await vault.storage.readText('.tylog/sync_trace.jsonl'),
      contains('"event":"indexed"'),
    );
  });
}
