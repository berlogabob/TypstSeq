import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/vault.dart';
import 'package:tylog_core/storage.dart';

/// Counts the I/O a rebuild performs, so a second rebuild over an unchanged
/// vault can be held to what it actually needs.
///
/// The costs this pins had no test at all: `rebuildIndex` re-read and decoded
/// `_index/index.json` on *every* call (8.8 MB plain on the real vault, 12.9k
/// objects reconstructed), re-encoded and re-hashed the whole index just to
/// decide whether to write it, and validation walked the vault a second time
/// on top of the scanner's own listing.
class _CountingStorage extends VaultStorage {
  _CountingStorage(this.inner);

  final VaultStorage inner;
  final reads = <String>[];
  final writes = <String>[];
  final listings = <String>[];

  @override
  Future<Uint8List> readBytes(String path) {
    reads.add(path);
    return inner.readBytes(path);
  }

  @override
  Future<void> writeBytes(String path, List<int> bytes) {
    writes.add(path);
    return inner.writeBytes(path, bytes);
  }

  @override
  Future<List<VaultStorageEntry>> list({
    String path = '',
    bool recursive = false,
  }) {
    if (recursive) listings.add(path);
    return inner.list(path: path, recursive: recursive);
  }

  @override
  Future<bool> exists(String path) => inner.exists(path);
  @override
  Future<void> createDirectory(String path) => inner.createDirectory(path);
  @override
  Future<VaultStorageEntry?> stat(String path) => inner.stat(path);
  @override
  Future<void> delete(String path) => inner.delete(path);
  @override
  Future<String> hash(String path) => inner.hash(path);

  void clear() {
    reads.clear();
    writes.clear();
    listings.clear();
  }
}

String _note(String id) =>
    '#import "/_system/tylog.typ" as tylog\n'
    '#show: tylog.note.with(id: "$id", title: "$id", kind: "note")\n'
    '= $id\n';

void main() {
  late Directory root;
  late _CountingStorage storage;
  late Vault vault;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('tylog-rebuild-twice');
    storage = _CountingStorage(LocalVaultStorage(root));
    vault = Vault.withStorage(storage);
    await vault.ensureCreated();
    for (var i = 0; i < 5; i++) {
      await storage.writeText('notes/n$i.typ', _note('n$i'));
    }
  });

  tearDown(() => root.delete(recursive: true));

  test('a second rebuild over an unchanged vault re-reads nothing it already '
      'holds', () async {
    await vault.rebuildIndex();
    storage.clear();

    await vault.rebuildIndex();

    expect(
      storage.reads.where((p) => p == Vault.indexPath),
      isEmpty,
      reason:
          'the index it just built is still in memory; re-reading and '
          're-decoding it is pure waste (8.8 MB plain on the real vault)',
    );
    expect(
      storage.writes.where((p) => p == Vault.indexPath),
      isEmpty,
      reason: 'nothing changed, so the index file must not be rewritten',
    );
    expect(
      storage.reads.where((p) => p.startsWith('notes/')),
      isEmpty,
      reason: 'unchanged notes are served from the cache',
    );
  });

  test('a rebuild walks the vault once, not once per consumer', () async {
    await vault.rebuildIndex();
    storage.clear();

    await vault.rebuildIndex();

    expect(
      storage.listings.length,
      lessThanOrEqualTo(1),
      reason:
          'the scanner already lists the whole tree; validation and the '
          'inspect-VFS must reuse that listing rather than repeat it '
          '(13,324 entries each on the real vault)',
    );
  });

  test('an edit still lands in the index', () async {
    await vault.rebuildIndex();
    // saveNote is the app's write path and marks the note stale for us.
    await vault.saveNote('notes/n1.typ', '${_note('n1')}\nchanged body\n');

    final index = await vault.rebuildIndex();

    expect(index.notesByPath['notes/n1.typ'], isNotNull);
    expect(
      storage.writes.where((p) => p == Vault.indexPath),
      isNotEmpty,
      reason: 'a real change must still be persisted',
    );
  });
}
