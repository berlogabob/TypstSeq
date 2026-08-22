import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tylog_core/maintenance.dart';
import 'package:tylog_core/models.dart';
import 'package:tylog_core/storage.dart';
import 'package:tylog_core/vault.dart';

/// Four processes write this vault — the UI isolate, the worker isolate, the
/// Android background service and the CLI — and the most frequent bug shape in
/// this codebase is a fix landing in one of them and being invisible in the
/// other three. The search-index identity guard lived only in the worker; the
/// orphan sweep only in the UI, which is the process *least* likely to be
/// killed mid-write; the donor load only in the app, so the CLI recompiled
/// everything every run and consumed nothing its peers published.
///
/// Two halves, and both are needed. The source scan says each context reaches
/// the routine and does not reach past it — a check that cannot be forgotten,
/// because it derives its answer from the source rather than from what someone
/// remembered to assert. The behavioural half says the routine actually does
/// each step, so the source scan cannot pass over a routine that does nothing.
///
/// And, as in `package_contract_test.dart`, the source scan carries a negative
/// control: a check with no proof it can fail is not a check.
void main() {
  group('every context runs the shared routine, and nothing around it', () {
    // The three contexts outside the UI isolate. Each one used to hold its own
    // copy of these steps.
    const contexts = {
      'lib/vault_worker.dart': 'the worker isolate',
      'lib/vault_service.dart': 'the Android background service',
      'packages/tylog_core/bin/tylog.dart': 'the CLI',
    };

    /// What a context must no longer do for itself: write a derived artifact.
    /// Each of these is a step the routine owns, and each one is a step some
    /// context used to do its own slightly different way.
    ///
    /// Deliberately not `scanVaultStorage(` — scanning is not the divergence.
    /// `tylog doctor` and `tylog dedupe` both scan without writing anything
    /// derived, one to print a report and one to decide which duplicates to
    /// delete, and neither is a maintenance pass. What must never fork is what
    /// gets *written*, because that is what the other three contexts then read.
    const forkedCalls = [
      'IndexDonorStore(',
      'PkmsSearchIndex.buildStorage(',
      '.saveStorage(',
      'TylogVaultPaths.index,',
    ];

    String read(String path) {
      final file = File(path);
      expect(
        file.existsSync(),
        isTrue,
        reason: 'run from the repo root; expected $path',
      );
      return file.readAsStringSync();
    }

    for (final entry in contexts.entries) {
      test('${entry.value} delegates', () {
        final source = read(entry.key);
        expect(
          source,
          contains('.run('),
          reason: '${entry.value} must go through VaultMaintenance.run',
        );
        for (final call in forkedCalls) {
          expect(
            source,
            isNot(contains(call)),
            reason:
                '${entry.value} does `$call` itself — that step belongs to '
                'VaultMaintenance, and a fix to it here would be invisible in '
                'the other three contexts',
          );
        }
      });
    }

    test('the scan would catch a context that forked the routine', () {
      // The negative control. VaultMaintenance itself makes every one of these
      // calls, so if the scan above could not see them it would be passing
      // vacuously — every context would look clean no matter what it did.
      final routine = read('packages/tylog_core/lib/src/maintenance.dart');
      for (final call in forkedCalls) {
        expect(routine, contains(call), reason: 'the scan can detect `$call`');
      }
    });
  });

  group('and the routine does every step', () {
    late Directory root;
    late LocalVaultStorage storage;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('tylog_maintenance_');
      storage = LocalVaultStorage(root);
      await storage.writeText(
        'notes/a.typ',
        '#import "/_system/tylog.typ" as tylog\n\n= A\n\nSome body text.\n',
      );
    });

    tearDown(() => root.delete(recursive: true));

    Future<List<VaultMaintenanceEvent>> run(
      VaultMaintenance maintenance, {
      String? deviceId,
    }) => maintenance.run(deviceId: deviceId, validate: true).toList();

    test('index, donor, validation, search and sweep, in that order', () async {
      // An orphan old enough to sweep, and one too young to.
      await storage.writeText('notes/a.typ.1700000000.tmp', 'orphan');
      await File(
        '${root.path}/notes/a.typ.1700000000.tmp',
      ).setLastModified(DateTime.now().subtract(const Duration(days: 2)));
      await storage.writeText('notes/b.typ.1700000001.tmp', 'still writing');

      final events = await run(VaultMaintenance(storage), deviceId: 'phone');

      expect(
        events.map((e) => e.runtimeType.toString()),
        containsAllInOrder([
          'MaintenanceIndexed',
          'MaintenanceValidated',
          'MaintenanceSearchBuilt',
          'MaintenanceSwept',
        ]),
        reason: 'the index must be published before the slower passes',
      );
      expect(await storage.exists(TylogVaultPaths.index), isTrue);
      expect(await storage.exists(TylogVaultPaths.searchIndex), isTrue);
      expect(
        await storage.exists('${TylogVaultPaths.indexDonors}/phone.json'),
        isTrue,
        reason: 'peers skip a full recompile only if the donor is published',
      );
      expect(
        events.whereType<MaintenanceSwept>().single.deleted,
        1,
        reason:
            'the old orphan goes, the one that may still be in flight stays',
      );
      expect(await storage.exists('notes/b.typ.1700000001.tmp'), isTrue);
    });

    test(
      'a second pass rewrites neither the index nor the search index',
      () async {
        // The guard that lived only in the worker: without it a no-op pass
        // re-encoded the whole corpus and rewrote megabytes of gzip for files
        // byte-identical to the ones already there — and on a Nextcloud-managed
        // desktop vault the rewritten files are then uploaded for nothing.
        final maintenance = VaultMaintenance(storage);
        await run(maintenance);
        final indexStamp = await storage.stat(TylogVaultPaths.index);
        final searchStamp = await storage.stat(TylogVaultPaths.searchIndex);

        final second = await run(maintenance);

        expect(
          second.whereType<MaintenanceSearchBuilt>().single.written,
          isFalse,
        );
        expect(
          (await storage.stat(TylogVaultPaths.index))?.modified,
          indexStamp?.modified,
        );
        expect(
          (await storage.stat(TylogVaultPaths.searchIndex))?.modified,
          searchStamp?.modified,
        );
      },
    );

    test('a peer donor is consumed, not just published', () async {
      // The CLI published one for years and read none, so the machine that can
      // index in seconds never saved itself the work its own peers had done.
      final laptop = VaultMaintenance(storage);
      await run(laptop, deviceId: 'laptop');
      // A phone arriving cold: no local index, only the laptop's donation.
      await storage.delete(TylogVaultPaths.index);

      final phone = VaultMaintenance(storage);
      await run(phone, deviceId: 'phone');

      expect(phone.donorReuse.devices, 1);
      expect(phone.donorReuse.notes, greaterThan(0));
    });

    test(
      'a validation report reaches the caller, with room for its own',
      () async {
        final events = await VaultMaintenance(storage)
            .run(
              extraProblems: (index) => [
                const PkmsProblem(
                  code: 'from-the-app-layer',
                  severity: PkmsSeverity.error,
                  subject: '_system',
                  message: 'rrule lives outside tylog_core',
                  fix: 'nothing',
                ),
              ],
            )
            .toList();

        final report = events.whereType<MaintenanceValidated>().single.report;
        expect(
          report.problems.map((p) => p.code),
          contains('from-the-app-layer'),
        );
      },
    );

    test('a step can be dropped, and only that step', () async {
      // The service drops validation deliberately: nothing there renders a
      // problems report. Everything else must still happen.
      final events = await VaultMaintenance(
        storage,
      ).run(deviceId: 'service', validate: false).toList();

      expect(events.whereType<MaintenanceValidated>(), isEmpty);
      expect(events.whereType<MaintenanceIndexed>(), hasLength(1));
      expect(events.whereType<MaintenanceSearchBuilt>(), hasLength(1));
      expect(events.whereType<MaintenanceSwept>(), hasLength(1));
    });
  });
}
