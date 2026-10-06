import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/nextcloud_sync.dart';
import 'package:tylog_core/storage.dart';
import 'package:tylog_core/scanner.dart';

/// Refuses one delete, to prove the sweep does not give up on the rest.
class _RefusingStorage extends LocalVaultStorage {
  _RefusingStorage(super.root, {required this.refuse});

  final String refuse;

  @override
  Future<void> delete(String path) async {
    if (path == refuse) throw const FileSystemException('locked');
    return super.delete(path);
  }
}

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('tylog_sweep_');
  });
  tearDown(() => root.delete(recursive: true));

  Future<void> aged(VaultStorage storage, String path) async {
    await storage.writeText(path, 'x');
    File(
      '${root.path}/$path',
    ).setLastModifiedSync(DateTime.now().subtract(const Duration(days: 2)));
  }

  test('one locked file does not abort the sweep', () async {
    // The whole loop sat inside a single catch, so an unlucky third file out
    // of 11,610 meant nothing after it was ever swept - silently, on every
    // open, forever.
    final storage = _RefusingStorage(root, refuse: 'notes/.a.tylog-1.tmp');
    await aged(storage, 'notes/.a.tylog-1.tmp');
    await aged(storage, 'notes/.b.tylog-2.tmp');
    await aged(storage, 'notes/.c.tylog-3.tmp');
    for (final name in ['a', 'b', 'c']) {
      await storage.writeText('notes/$name', 'committed');
    }

    expect(await sweepVaultLeftovers(storage), 2);
    expect(await storage.exists('notes/.a.tylog-1.tmp'), isTrue);
    expect(await storage.exists('notes/.b.tylog-2.tmp'), isFalse);
    expect(await storage.exists('notes/.c.tylog-3.tmp'), isFalse);
  });

  test(
    'sweep preserves missing targets until scan recovers their copies',
    () async {
      final storage = LocalVaultStorage(root);
      for (final suffix in ['tmp', 'backup']) {
        await aged(storage, 'notes/.lost-$suffix.typ.tylog-1.$suffix');
        await aged(storage, 'notes/.kept-$suffix.typ.tylog-2.$suffix');
        await storage.writeText('notes/kept-$suffix.typ', 'committed');
      }
      expect(await sweepVaultLeftovers(storage), 2);
      final entries = await storage.list(recursive: true);
      final index = await scanVaultStorage(storage, entries: entries);
      for (final suffix in ['tmp', 'backup']) {
        expect(index.notesByPath, contains('notes/lost-$suffix.typ'));
        expect(await storage.readText('notes/lost-$suffix.typ'), 'x');
        expect(
          await storage.exists('notes/.lost-$suffix.typ.tylog-1.$suffix'),
          isFalse,
        );
        expect(await storage.readText('notes/kept-$suffix.typ'), 'committed');
      }
    },
  );

  test('a fresh temp file is left alone', () async {
    final storage = LocalVaultStorage(root);
    await storage.writeText('notes/.fresh.tylog-9.tmp', 'in flight');

    expect(await sweepVaultLeftovers(storage), 0);
    expect(await storage.exists('notes/.fresh.tylog-9.tmp'), isTrue);
  });

  test('real notes are never swept', () async {
    final storage = LocalVaultStorage(root);
    await aged(storage, 'notes/real.typ');
    await aged(storage, 'notes/scratch.tmp');

    expect(await sweepVaultLeftovers(storage), 0);
    expect(await storage.exists('notes/real.typ'), isTrue);
    expect(await storage.exists('notes/scratch.tmp'), isTrue);
  });
}
