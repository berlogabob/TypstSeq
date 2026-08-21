import 'package:flutter/widgets.dart';

import 'nextcloud_sync.dart';
import 'scanner.dart';
import 'search_index.dart';
import 'vault.dart';
import 'vault_lock.dart';
import 'vault_registry.dart';
import 'vault_storage.dart';

/// Headless entrypoint: one closed-app sync+reindex pass, then exit.
///
/// Hosted by `VaultSyncWorker` (Android) in its own FlutterEngine — no UI, no
/// SendPorts, a fresh root isolate — so unlike [vaultWorkerMain] it takes no
/// arguments and reconstructs everything from persisted state. The engine's
/// plugins (path_provider, flutter_secure_storage, the SafBridge channel) are
/// registered by the host before this runs.
///
/// Deliberately conservative: it takes the vault lock or leaves, honours the
/// conflict gate the same way the UI's auto-sync does, and never calls
/// `ensureCreated()` — a background pass must not up/downgrade the vault's
/// managed Typst files.
@pragma('vm:entry-point')
Future<void> vaultServiceMain() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await _runOnce();
  } catch (error) {
    debugPrint('vaultServiceMain failed: $error');
  } finally {
    // Always tell the host we are done — a swallowed error must not leave the
    // worker waiting out its timeout.
    try {
      await AndroidTreeVaultStorage.channel.invokeMethod<void>(
        'backgroundDone',
      );
    } catch (_) {}
  }
}

Future<void> _runOnce() async {
  final registry = await VaultRegistry.load();
  if (registry.entries.isEmpty) return;
  final entry = registry.active;
  final cloud = entry.cloud;
  if (cloud == null || !cloud.isReady) return;
  final storage = entry.storage;
  final vault = Vault.withStorage(storage);

  if (!await VaultLock.acquire(storage, 'service')) {
    debugPrint('vaultService: UI holds the vault lock, skipping');
    return;
  }
  try {
    // The conflict gate stays authoritative in the background too.
    if ((await loadSyncConflicts(vault)).isNotEmpty) {
      debugPrint('vaultService: conflicts pending, sync stays suspended');
      return;
    }
    // Cheap Depth:0 etag probe first — most periodic runs find nothing new
    // and should cost one request, not a full crawl.
    if (await NextcloudSync(cloud).pollIsUnchanged(vault, dirty: false)) {
      return;
    }
    final result = await NextcloudSync(
      cloud,
    ).sync(vault, trigger: 'background');
    if (!result.requiresIndexRefresh) return;

    FlutterTypstInspector? inspector;
    try {
      inspector = await FlutterTypstInspector.create();
    } catch (_) {
      // Native Typst stays optional; the scanner falls back to source parsing.
    }
    try {
      final index = await vault.rebuildIndex(
        inspector: inspector,
        deviceId: registry.deviceId,
      );
      // Refresh the search index too, so the next app open starts warm
      // instead of paying the SAF-heavy build on the user's time.
      final cached = await PkmsSearchIndex.loadStorage(
        storage,
        Vault.searchIndexPath,
      );
      final search = await PkmsSearchIndex.buildStorage(
        storage,
        index,
        previous: cached,
      );
      // buildStorage returns the *same instance* when every note hit the
      // cache and the key set is unchanged, so identity is an exact "nothing
      // to write" test. Without it a no-op scan re-encoded ~43 MB of JSON and
      // rewrote ~12 MB of gzip for a file byte-identical to the one already
      // there. vault_worker.dart has always had this guard; these two paths
      // did not.
      if (!identical(search, cached)) {
        await search.saveStorage(storage, Vault.searchIndexPath);
      }
    } finally {
      inspector?.dispose();
    }
  } finally {
    await VaultLock.release(storage, 'service');
  }
}
