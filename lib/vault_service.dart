import 'dart:async';

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
/// How long a single background run may take before the platform kills it.
///
/// Must stay in step with `VaultSyncWorker.TIMEOUT_MILLIS`; the test in
/// `test/vault_lock_test.dart` pins the two together, because nothing else
/// stops one constant in Kotlin and one in Dart drifting apart — which is
/// precisely how a lock outlived the process holding it.
const backgroundRunBudget = Duration(minutes: 9);

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

  // Declare the ceiling the platform actually enforces. WorkManager destroys
  // this engine at `VaultSyncWorker.TIMEOUT_MILLIS` without unwinding Dart, so
  // the `finally` below — and with it VaultLock.release — simply does not run.
  // Saying so up front means the lock expires exactly when the process can no
  // longer be holding it, instead of a minute later.
  final deadline = DateTime.now().add(backgroundRunBudget);
  if (!await VaultLock.acquire(
    storage,
    'service',
    validFor: backgroundRunBudget,
  )) {
    debugPrint('vaultService: UI holds the vault lock, skipping');
    return;
  }
  try {
    // No conflict gate. This path kept the blanket suspend that the foreground
    // dropped, so one pending record still stopped the whole vault syncing —
    // on the *unattended* path, which is the one that runs for hours and caused
    // the original 695-article stall. It was also self-perpetuating: the three
    // repairs that clear such a record (the donor-conflict discard,
    // _refreshConflictRemote and _markConflictRemoteDeleted) all live inside
    // sync(), i.e. behind this gate. The loop skips conflicted paths one by one
    // and pollIsUnchanged already refuses to shortcut while a conflict is
    // pending, so nothing else was relying on it.
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
    Object? inspectorError;
    try {
      inspector = await FlutterTypstInspector.create();
    } catch (error) {
      // Native Typst stays optional; the scanner falls back to source parsing.
      // But this process runs unattended for hours, so swallowing the reason
      // meant the context with the least observability had none at all: a
      // background rebuild could degrade the whole vault to source parsing
      // with nothing anywhere recording why.
      inspectorError = error;
    }
    try {
      final index = await vault.rebuildIndex(
        inspector: inspector,
        deviceId: registry.deviceId,
        // Stop cooperatively before the platform stops us mid-write. The
        // scanner already honours this hook; the service was the one caller
        // that passed nothing, so a cold rebuild was guaranteed to be killed
        // partway on a large vault.
        isCancelled: () => DateTime.now().isAfter(deadline),
      );
      // The trace is the only channel this process has — it raises no
      // PkmsProblems, because nothing here renders them.
      unawaited(
        appendVaultTrace(vault, [
          {
            'timestamp': DateTime.now().toUtc().toIso8601String(),
            'event': 'indexed',
            'trigger': 'background',
            'notes': index.notes.length,
            'tasks': index.tasks.length,
            'reusedNotes': vault.donorReuse.notes,
            'reusedDevices': vault.donorReuse.devices,
            'skippedDonors': vault.donorReuse.skipped,
            if (inspectorError != null)
              'errorMessage': 'Native Typst did not start: $inspectorError',
            if (vault.donorPublishError != null)
              'donorPublishError': '${vault.donorPublishError}',
          },
        ]).catchError((_) {}),
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
    // This process is the one most likely to be killed mid-write — WorkManager
    // destroys the engine on timeout — and it is the reason the temp grace
    // period exists, yet it never swept. The orphans it created waited for the
    // next time a human opened the app.
    await sweepVaultLeftovers(storage);
  } finally {
    await VaultLock.release(storage, 'service');
  }
}
