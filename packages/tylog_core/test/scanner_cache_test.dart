import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:tylog_core/models.dart';
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
  Future<String> hash(String path) {
    hashes.add(path);
    return inner.hash(path);
  }

  final hashes = <String>[];
}

/// Counts Typst queries. Skipping *those* is what the content-hash gate buys —
/// a re-read is milliseconds, an inspection is a Typst compile.
class _CountingInspector implements TypstInspector {
  final inspected = <String>[];

  @override
  Future<List<TypstMetadataRecord>> inspect(TypstDocumentInput input) async {
    inspected.add(input.path);
    final title = RegExp(r'title: "([^"]*)"').firstMatch(input.source)?.group(1);
    return [
      TypstMetadataRecord(
        label: '<tylog-note>',
        value: {
          'schema': 1,
          'entity': 'note',
          'id': input.path.split('/').last.replaceFirst('.typ', ''),
          'title': title ?? 'Untitled',
          'kind': 'note',
        },
      ),
    ];
  }
}

String _note(String title) =>
    '#show: tylog.note.with(\n'
    '  id: "a",\n'
    '  title: "$title",\n'
    '  kind: "note",\n'
    ')\n';

void main() {
  group('single read', _singleReadTests);

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

  group('content hash', () {
    /// Restamps every fingerprint the way another device would: same bytes,
    /// different mtime. This is what a laptop-built index looks like to the
    /// phone, where SAF reports its own mtimes.
    VaultIndex asIfBuiltElsewhere(VaultIndex index) => VaultIndex(
      version: index.version,
      notesByPath: {
        for (final entry in index.notesByPath.entries)
          entry.key: entry.value.copyWith(fingerprint: 'foreign-mtime:0'),
      },
      backlinksByTarget: index.backlinksByTarget,
      tasks: index.tasks,
    );

    test('a foreign index is reused without re-querying Typst', () async {
      final inspector = _CountingInspector();
      final first = await scanVaultStorage(storage, inspector: inspector);
      expect(inspector.inspected, hasLength(2), reason: 'cold build inspects');

      inspector.inspected.clear();
      storage.reads.clear();
      final second = await scanVaultStorage(
        storage,
        inspector: inspector,
        previous: asIfBuiltElsewhere(first),
      );

      expect(
        inspector.inspected,
        isEmpty,
        reason: 'the bytes are unchanged, so no note needs a Typst query',
      );
      expect(storage.reads, isEmpty, reason: 'hashing does not read via readBytes');
      expect(storage.hashes, containsAll(['notes/a.typ', 'notes/b.typ']));
      expect(second.notesByPath['notes/a.typ']?.title, 'Alpha');
    });

    test('the reused entry re-stamps the cheap gate, so the next scan is free', () async {
      final inspector = _CountingInspector();
      final first = await scanVaultStorage(storage, inspector: inspector);
      final second = await scanVaultStorage(
        storage,
        inspector: inspector,
        previous: asIfBuiltElsewhere(first),
      );

      storage.hashes.clear();
      storage.reads.clear();
      await scanVaultStorage(storage, inspector: inspector, previous: second);

      expect(storage.hashes, isEmpty, reason: 'mtime+size gate hits first');
      expect(storage.reads, isEmpty);
    });

    test('changed bytes still fall through to a full re-parse', () async {
      final inspector = _CountingInspector();
      final first = await scanVaultStorage(storage, inspector: inspector);
      final beforeHash = first.notesByPath['notes/a.typ']!.contentHash;
      expect(beforeHash, isNotNull);

      await storage.writeText('notes/a.typ', _note('Alpry'));

      inspector.inspected.clear();
      final second = await scanVaultStorage(
        storage,
        inspector: inspector,
        previous: asIfBuiltElsewhere(first),
      );

      expect(inspector.inspected, ['notes/a.typ']);
      expect(second.notesByPath['notes/a.typ']?.title, 'Alpry');
      expect(
        second.notesByPath['notes/a.typ']?.contentHash,
        isNot(beforeHash),
        reason: 'the stored hash must follow the new bytes',
      );
      expect(second.notesByPath['notes/b.typ']?.contentHash, isNotNull);
    });

    test('an index from an older schema is a total miss', () async {
      final inspector = _CountingInspector();
      final first = await scanVaultStorage(storage, inspector: inspector);
      final legacy = VaultIndex(
        version: kVaultIndexVersion - 1,
        notesByPath: first.notesByPath,
        backlinksByTarget: first.backlinksByTarget,
      );

      inspector.inspected.clear();
      final second = await scanVaultStorage(
        storage,
        inspector: inspector,
        previous: legacy,
      );

      expect(inspector.inspected, hasLength(2));
      expect(second.version, kVaultIndexVersion);
    });
  });
}

/// The scan reads each note once and hashes those same bytes. If that hash
/// ever disagreed with `storage.hash`, every cached entry would miss and the
/// whole vault would silently re-parse on the next scan.
void _singleReadTests() {
  test('the scanned content hash matches storage.hash exactly', () async {
    final root = await Directory.systemTemp.createTemp('tylog_hash_');
    addTearDown(() => root.delete(recursive: true));
    final storage = LocalVaultStorage(root);
    await storage.writeText('notes/a.typ', _note('Alpha'));
    // Non-ASCII: the bytes hashed must be the file's bytes, not a re-encoding.
    await storage.writeText('notes/b.typ', _note('Приве́т — ünïcode'));

    final index = await scanVaultStorage(storage);

    for (final note in index.notes) {
      expect(
        note.contentHash,
        await storage.hash(note.path),
        reason: '${note.path} would miss its cache on the next scan',
      );
    }
  });

  test('a note is read once per scan, not twice', () async {
    final root = await Directory.systemTemp.createTemp('tylog_reads_');
    addTearDown(() => root.delete(recursive: true));
    final storage = _CountingStorage(LocalVaultStorage(root));
    await storage.writeText('notes/a.typ', _note('Alpha'));

    storage.reads.clear();
    storage.hashes.clear();
    await scanVaultStorage(storage);

    expect(
      storage.reads.where((p) => p == 'notes/a.typ'),
      hasLength(1),
      reason: 'readText + storage.hash was two full reads per note',
    );
    expect(storage.hashes, isEmpty, reason: 'the bytes in hand are hashed');
  });
}
