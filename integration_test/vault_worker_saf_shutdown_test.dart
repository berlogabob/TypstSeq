import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tylog/vault_registry.dart';
import 'package:tylog/vault_storage.dart';
import 'package:tylog/vault_worker.dart';

/// Profile-only regression for disposing a worker while an Android SAF read is
/// active. The marker and name guard make every write disposable `_index`
/// maintenance on the coordinator-created audit vault.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'disposing an active SAF worker drains before replacement',
    (_) async {
      final registry = await VaultRegistry.load();
      final entry = registry.active;
      expect(entry.storageKind, 'android-tree');
      expect(entry.name, 'TyLogAuditVault');
      final storage = entry.storage;
      expect(storage, isA<AndroidTreeVaultStorage>());
      final saf = storage as AndroidTreeVaultStorage;
      expect(await saf.hasAccess(), isTrue);
      expect(await storage.readText('README-AUDIT.txt'), 'TyLogAuditVault\n');

      final worker = await VaultWorkerClient.spawn(entry: entry);
      final stream = worker
          .run(const RebuildIndexCommand(force: true, stale: {}))
          .asBroadcastStream();
      final eventsFuture = stream.toList();
      final started = Completer<void>();
      stream.listen((event) {
        if (event is IndexProgressEvent && !started.isCompleted) {
          started.complete();
        }
      });
      await started.future;

      await worker.dispose();
      await worker.dispose();
      final events = await eventsFuture;
      final terminal = events
          .where((event) => event is WorkDoneEvent || event is WorkFailedEvent)
          .toList();
      expect(terminal, hasLength(1));
      expect(terminal.single, isA<WorkFailedEvent>());
      expect((terminal.single as WorkFailedEvent).cancelled, isTrue);
      expect(events.whereType<WorkDoneEvent>(), isEmpty);

      final replacement = await VaultWorkerClient.spawn(entry: entry);
      addTearDown(replacement.dispose);
      final replacementEvents = await replacement
          .run(const RebuildIndexCommand(stale: {}))
          .toList();
      expect(replacementEvents.whereType<WorkFailedEvent>(), isEmpty);
      expect(replacementEvents.last, isA<WorkDoneEvent>());
    },
    skip: !Platform.isAndroid,
  );
}
