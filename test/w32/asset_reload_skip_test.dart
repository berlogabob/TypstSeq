// ignore_for_file: depend_on_referenced_packages
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/app_mobile.dart';
import 'package:tylog/vault.dart';
import 'package:tylog/vault_storage.dart';

Future<void> _emptyStartup() async {}

void main() {
  testWidgets('unchanged referenced assets skip reloads while typing', (
    tester,
  ) async {
    final storage = _MemoryStorage();
    await storage.writeBytes('assets/a.png', [1, 2, 3]);
    await tester.pumpWidget(
      const MaterialApp(home: HomeScreen(startup: _emptyStartup)),
    );
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    final dynamic home = tester.state(find.byType(HomeScreen));
    home.workspace.vault = Vault.withStorage(storage);

    const source = '#image("assets/a.png")';
    await tester.runAsync(() => home.refreshNoteAssetsForTesting(source));
    final readsAfterInitialLoad = storage.readBytesCalls;
    expect(readsAfterInitialLoad, greaterThanOrEqualTo(1));

    for (var i = 1; i <= 10; i++) {
      await tester.runAsync(
        () => home.refreshNoteAssetsForTesting('$source${'x' * i}'),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(storage.readBytesCalls, readsAfterInitialLoad);

    await tester.runAsync(
      () => home.refreshNoteAssetsForTesting(source, force: true),
    );
    expect(storage.readBytesCalls, greaterThan(readsAfterInitialLoad));
    await tester.pumpWidget(const SizedBox());
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));
}

class _MemoryStorage extends VaultStorage {
  final Map<String, Uint8List> _files = {};
  final Set<String> _directories = {''};
  int readBytesCalls = 0;

  @override
  Future<void> createDirectory(String path) async {
    if (path.isEmpty) return;
    final parts = path.split('/');
    for (var i = 1; i <= parts.length; i++) {
      _directories.add(parts.take(i).join('/'));
    }
  }

  @override
  Future<void> delete(String path) async =>
      _files.removeWhere((key, _) => key == path || key.startsWith('$path/'));

  @override
  Future<bool> exists(String path) async =>
      _files.containsKey(path) || _directories.contains(path);

  @override
  Future<String> hash(String path) async =>
      sha256.convert(_files[path]!).toString();

  @override
  Future<List<VaultStorageEntry>> list({
    String path = '',
    bool recursive = false,
  }) async {
    final prefix = path.isEmpty ? '' : '$path/';
    bool included(String candidate) =>
        candidate.startsWith(prefix) &&
        candidate != path &&
        (recursive || !candidate.substring(prefix.length).contains('/'));
    return [
      for (final directory in _directories)
        if (included(directory))
          VaultStorageEntry(path: directory, isDirectory: true),
      for (final entry in _files.entries)
        if (included(entry.key))
          VaultStorageEntry(
            path: entry.key,
            isDirectory: false,
            size: entry.value.length,
            modified: DateTime.utc(2026, 7, 14),
          ),
    ];
  }

  @override
  Future<Uint8List> readBytes(String path) async {
    readBytesCalls++;
    return _files[path]!;
  }

  @override
  Future<VaultStorageEntry?> stat(String path) async {
    final bytes = _files[path];
    if (bytes != null) {
      return VaultStorageEntry(
        path: path,
        isDirectory: false,
        size: bytes.length,
        modified: DateTime.utc(2026, 7, 14),
      );
    }
    return _directories.contains(path)
        ? VaultStorageEntry(path: path, isDirectory: true)
        : null;
  }

  @override
  Future<void> writeBytes(String path, List<int> bytes) async {
    final slash = path.lastIndexOf('/');
    if (slash > 0) await createDirectory(path.substring(0, slash));
    _files[path] = Uint8List.fromList(bytes);
  }
}
