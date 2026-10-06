import 'dart:io';

import 'package:test/test.dart';
import 'package:tylog_core/tylog_core.dart';

class _Inspector implements TypstInspector {
  int calls = 0;

  @override
  Future<List<TypstMetadataRecord>> inspect(TypstDocumentInput input) async {
    calls++;
    return const [];
  }
}

void main() {
  late Directory root;
  late LocalVaultStorage storage;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('tylog-phone-donor-');
    storage = LocalVaultStorage(root);
    await storage.writeText('notes/a.typ', '= A\n');
    await storage.writeText('notes/b.typ', '= B\n');
  });
  tearDown(() => root.delete(recursive: true));

  Future<MaintenanceIndexed> run(
    VaultMaintenance maintenance,
    String id, {
    TypstInspector? inspector,
    bool force = false,
  }) async {
    final events = await maintenance
        .run(
          deviceId: id,
          inspector: inspector,
          force: force,
          validate: false,
          buildSearch: false,
          sweep: false,
        )
        .toList();
    return events.whereType<MaintenanceIndexed>().single;
  }

  test(
    'phone reuses fresh hashes on warm and forced scans without publishing',
    () async {
      await run(VaultMaintenance(storage, publishDonor: true), 'cli-mac');
      // A current local index must not prevent consultation of the Mac donor.
      final before = await storage.stat('notes/b.typ');
      await storage.writeText('notes/b.typ', '= C\n');
      File('${root.path}/notes/b.typ').setLastModifiedSync(before!.modified!);
      final inspector = _Inspector();
      final phone = VaultMaintenance(storage, publishDonor: false);
      final first = await run(phone, 'phone', inspector: inspector);
      expect(first.parsedNotes, 1);
      expect(first.donorReuse.notes, 1);
      expect(first.donorReuse.devices, 1);
      expect(inspector.calls, 1);
      expect(first.durationMs, greaterThanOrEqualTo(0));
      expect(await storage.exists('_system/index/phone.json'), isFalse);

      final forced = await run(
        phone,
        'phone',
        inspector: inspector,
        force: true,
      );
      expect(forced.parsedNotes, 1);
      expect(forced.donorReuse.notes, 1);
      expect(inspector.calls, 2);
      expect(await storage.exists('_system/index/phone.json'), isFalse);
    },
  );

  test(
    'phone skips donors older than 24h and never prunes; desktop prunes',
    () async {
      final desktop = VaultMaintenance(storage, publishDonor: true);
      await run(desktop, 'mac');
      final donor = File('${root.path}/_system/index/mac.json');
      donor.setLastModifiedSync(
        DateTime.now().subtract(const Duration(hours: 25)),
      );
      await storage.delete(TylogVaultPaths.index);
      final phone = await run(
        VaultMaintenance(storage, publishDonor: false),
        'phone',
      );
      expect(phone.parsedNotes, 2);
      expect(phone.donorReuse.notes, 0);
      expect(phone.donorReuse.skipped, 1);

      final retired = File('${root.path}/_system/index/retired.json');
      retired.writeAsStringSync(donor.readAsStringSync());
      retired.setLastModifiedSync(
        DateTime.now().subtract(const Duration(days: 31)),
      );
      await run(VaultMaintenance(storage, publishDonor: false), 'phone');
      expect(retired.existsSync(), isTrue);
      await run(desktop, 'mac');
      expect(retired.existsSync(), isFalse);
      expect(donor.existsSync(), isTrue);
    },
  );
}
