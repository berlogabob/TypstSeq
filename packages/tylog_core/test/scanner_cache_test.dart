import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:tylog_core/scanner.dart';
import 'package:tylog_core/storage.dart';

/// Counts reads so a test can assert the scan cache actually skipped a file
/// rather than re-reading and happening to produce the same result.
class _CountingStorage extends VaultStorage {
  _CountingStorage(this.inner);

  final VaultStorage inner;
  final reads = <String>[];

  @override
  Future<Uint8List> readBytes(String path) {
    reads.add(path);
    return inner.readBytes(path);
  }

  @override
  Future<bool> exists(String path) => inner.exists(path);
  @override
  Future<void> createDirectory(String path) => inner.createDirectory(path);
  @override
  Future<List<VaultStorageEntry>> list({
    String path = '',
    bool recursive = false,
  }) => inner.list(path: path, recursive: recursive);
  @override
  Future<VaultStorageEntry?> stat(String path) => inner.stat(path);
  @override
  Future<void> writeBytes(String path, List<int> bytes) =>
      inner.writeBytes(path, bytes);
  @override
  Future<void> delete(String path) => inner.delete(path);
  @override
  Future<String> hash(String path) => inner.hash(path);
}

String _note(String title) =>
    '#show: tylog.note.with(\n'
    '  id: "a",\n'
    '  title: "$title",\n'
    '  kind: "note",\n'
    ')\n';

void main() {
  late Directory root;
  late _CountingStorage storage;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('tylog-scan-cache');
    storage = _CountingStorage(LocalVaultStorage(root));
    await storage.writeText('notes/a.typ', _note('Alpha'));
    await storage.writeText('notes/b.typ', _note('Bravo'));
  });

  tearDown(() => root.delete(recursive: true));

  test('an unchanged note is served from cache without being re-read', () async {
    final first = await scanVaultStorage(storage);
    expect(first.notes, hasLength(2));

    storage.reads.clear();
    final second = await scanVaultStorage(storage, previous: first);

    expect(storage.reads, isEmpty, reason: 'cache hit must not read the file');
    expect(second.notes.map((n) => n.path), first.notes.map((n) => n.path));
  });

  test('force re-reads everything', () async {
    final first = await scanVaultStorage(storage);

    storage.reads.clear();
    await scanVaultStorage(storage, previous: first, force: true);

    expect(storage.reads, containsAll(['notes/a.typ', 'notes/b.typ']));
  });

  test('a stale path is re-read even when its fingerprint is unchanged', () async {
    final first = await scanVaultStorage(storage);
    expect(first.notesByPath['notes/a.typ']?.title, 'Alpha');

    // Same byte length, so mtime+size can collide with the previous scan when
    // both land inside one second — exactly the hole `stale` exists to close.
    await storage.writeText('notes/a.typ', _note('Alpry'));

    final second = await scanVaultStorage(
      storage,
      previous: first,
      stale: {'notes/a.typ'},
    );

    expect(second.notesByPath['notes/a.typ']?.title, 'Alpry');
    expect(second.notesByPath['notes/b.typ']?.title, 'Bravo');
  });

  test('stale does not force a rescan of other notes', () async {
    final first = await scanVaultStorage(storage);

    storage.reads.clear();
    await scanVaultStorage(storage, previous: first, stale: {'notes/a.typ'});

    expect(storage.reads, ['notes/a.typ']);
  });
}
