import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/import/legacy_import_plan.dart';
import 'package:tylog_core/storage.dart';

class _Storage extends VaultStorage {
  _Storage(this.entries);
  final List<VaultStorageEntry> entries;
  @override
  Future<bool> exists(String path) async => true;
  @override
  Future<void> createDirectory(String path) async {}
  @override
  Future<List<VaultStorageEntry>> list({
    String path = '',
    bool recursive = false,
  }) async => entries;
  @override
  Future<VaultStorageEntry?> stat(String path) async => null;
  @override
  Future<Uint8List> readBytes(String path) async => Uint8List(0);
  @override
  Future<void> writeBytes(String path, List<int> bytes) async {}
  @override
  Future<void> delete(String path) async {}
  @override
  Future<String> hash(String path) async => '';
}

VaultStorageEntry file(String path, {int size = 1, DateTime? modified}) =>
    VaultStorageEntry(
      path: path,
      isDirectory: false,
      size: size,
      modified: modified,
    );

void main() {
  test('sorts and fingerprints metadata deterministically', () async {
    final a = _Storage([file('pages/b.md'), file('pages/a.md')]);
    final b = _Storage([file('pages/a.md'), file('pages/b.md')]);
    final ma = await buildLegacyImportManifest(a, LegacyImportDialect.logseq);
    final mb = await buildLegacyImportManifest(b, LegacyImportDialect.logseq);
    expect(ma.entries.map((e) => e.path), ['pages/a.md', 'pages/b.md']);
    expect(ma.fingerprint, mb.fingerprint);
  });

  test('classifies all files, including hidden Obsidian files', () async {
    final manifest = await buildLegacyImportManifest(
      _Storage([
        file('journals/2024_01_01.md'),
        file('pages/a.md'),
        file('assets/x.png'),
        file('.obsidian/app.json'),
        file('.obsidian/template.md'),
        file('misc/readme.md'),
        file('other.bin'),
        VaultStorageEntry(path: 'pages', isDirectory: true),
      ]),
      LegacyImportDialect.logseq,
    );
    expect(manifest.entries.map((e) => e.kind), [
      LegacyImportEntryKind.unsupported,
      LegacyImportEntryKind.unsupported,
      LegacyImportEntryKind.asset,
      LegacyImportEntryKind.journal,
      LegacyImportEntryKind.unsupported,
      LegacyImportEntryKind.unsupported,
      LegacyImportEntryKind.page,
    ]);
  });

  test('rejects unsafe and duplicate paths', () async {
    expect(
      () => buildLegacyImportManifest(
        _Storage([file('../x.md')]),
        LegacyImportDialect.logseq,
      ),
      throwsArgumentError,
    );
    expect(
      () => buildLegacyImportManifest(
        _Storage([file('a.md'), file('a.md')]),
        LegacyImportDialect.logseq,
      ),
      throwsStateError,
    );
  });

  test(
    'metadata changes fingerprint and dialect is part of fingerprint',
    () async {
      final one = await buildLegacyImportManifest(
        _Storage([file('a.md', size: 1)]),
        LegacyImportDialect.logseq,
      );
      final two = await buildLegacyImportManifest(
        _Storage([file('a.md', size: 2)]),
        LegacyImportDialect.logseq,
      );
      final three = await buildLegacyImportManifest(
        _Storage([file('a.md', size: 1)]),
        LegacyImportDialect.obsidian,
      );
      expect(one.fingerprint, isNot(two.fingerprint));
      expect(one.fingerprint, isNot(three.fingerprint));
    },
  );
}
