import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';

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

class _ReceiptStorage extends LocalVaultStorage {
  _ReceiptStorage(super.root);
  List<VaultStorageEntry>? notes;
  int bodyReads = 0;
  int hashReads = 0;

  @override
  Future<Uint8List> readBytes(String path) async {
    if (path.startsWith('notes/')) bodyReads++;
    return super.readBytes(path);
  }

  @override
  Future<String> hash(String path) async {
    if (path.startsWith('notes/')) hashReads++;
    return super.hash(path);
  }

  @override
  Future<List<VaultStorageEntry>> list({
    String path = '',
    bool recursive = false,
  }) async {
    final entries = await super.list(path: path, recursive: recursive);
    if (recursive && notes != null) {
      return [
        ...entries.where((entry) => !entry.path.startsWith('notes/')),
        ...notes!,
      ];
    }
    return entries;
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
    'cold and warm 6731-note donor adoption reads zero note bodies',
    () async {
      final receipts = _ReceiptStorage(root);
      final hash = await storage.hash('notes/a.typ');
      final stamp = DateTime(2020);
      receipts.notes = List.generate(
        6731,
        (i) => VaultStorageEntry(
          path: 'notes/$i.typ',
          isDirectory: false,
          size: 4,
          modified: stamp,
        ),
      );
      final donorIndex = VaultIndex(
        notesByPath: {
          for (final entry in receipts.notes!)
            entry.path: scanNote(
              entry.path,
              '= A\n',
            ).copyWith(contentHash: hash),
        },
        backlinksByTarget: {},
      );
      await IndexDonorStore(receipts).publish('cli-mac', donorIndex);
      await receipts.writeText(
        '.tylog/sync_state.json',
        jsonEncode({
          'schema': 2,
          'cursors': {
            for (final entry in receipts.notes!)
              entry.path: {
                'localSha256': hash,
                'localMillis': stamp.millisecondsSinceEpoch,
                'localSize': 4,
              },
          },
        }),
      );
      await receipts.delete(TylogVaultPaths.index);
      final phone = VaultMaintenance(receipts, publishDonor: false);
      for (final force in [false, false, true]) {
        final indexed = await run(phone, 'phone', force: force);
        expect(indexed.index.notes.length, 6731);
        expect(indexed.parsedNotes, 0);
        expect(indexed.donorReuse.notes, 6731);
        expect(receipts.bodyReads, 0);
        expect(receipts.hashReads, 0);
        expect(indexed.durationMs, lessThan(20000));
      }
    },
  );

  test(
    'changed receipt stamps and stale local writes must read bodies',
    () async {
      final receipts = _ReceiptStorage(root);
      await run(VaultMaintenance(receipts, publishDonor: true), 'cli-mac');
      final entry = (await receipts.stat('notes/a.typ'))!;
      await receipts.writeText(
        '.tylog/sync_state.json',
        jsonEncode({
          'schema': 2,
          'cursors': {
            'notes/a.typ': {
              'localSha256': await receipts.hash(entry.path),
              'localMillis': entry.modified!.millisecondsSinceEpoch,
              'localSize': entry.size,
            },
          },
        }),
      );
      await receipts.writeText(entry.path, '= edited\n');
      receipts.bodyReads = receipts.hashReads = 0;
      final phone = VaultMaintenance(receipts, publishDonor: false);
      final index = await phone.buildIndex(stale: {entry.path});
      expect(
        index.notesByPath[entry.path]!.contentHash,
        await storage.hash(entry.path),
      );
      expect(receipts.bodyReads, greaterThan(0));
      expect(receipts.hashReads, greaterThan(0));
    },
  );

  test(
    'same-stamp receipt edits are hashed across restart and receipt window',
    () async {
      final receipts = _ReceiptStorage(root);
      await run(VaultMaintenance(receipts, publishDonor: true), 'cli-mac');
      final entry = (await receipts.stat('notes/a.typ'))!;
      final oldHash = await receipts.hash(entry.path);
      for (final recent in [true, false]) {
        final stamp = recent ? DateTime.now() : DateTime(2020);
        await receipts.writeText(
          '.tylog/sync_state.json',
          jsonEncode({
            'schema': 2,
            'cursors': {
              entry.path: {
                'localSha256': oldHash,
                'localMillis': stamp.millisecondsSinceEpoch,
                'localSize': 4,
              },
            },
          }),
        );
        if (recent) {
          // An external same-second edit has no app write marker.
          await File('${root.path}/${entry.path}').writeAsString('= C\n');
        } else {
          await receipts.writeText(entry.path, '= D\n');
        }
        receipts.notes = [
          VaultStorageEntry(
            path: entry.path,
            isDirectory: false,
            size: 4,
            modified: stamp,
          ),
        ];
        File('${root.path}/${entry.path}').setLastModifiedSync(stamp);
        // New maintenance instance models a process restart losing memory sets.
        final index = await VaultMaintenance(
          receipts,
          publishDonor: false,
        ).buildIndex();
        expect(
          index.notesByPath[entry.path]!.contentHash,
          await storage.hash(entry.path),
          reason: 'recent=$recent',
        );
      }
    },
  );

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
