// ignore_for_file: depend_on_referenced_packages
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/app_mobile.dart';
import 'package:tylog/models.dart';
import 'package:tylog/vault.dart';
import 'package:tylog/vault_storage.dart';

Future<void> _emptyStartup() async {}

const _past = 'daily/2026/10/2026-10-20.typ';
const _source =
    '#import "/_system/tylog.typ" as tylog\n\n'
    '#show: tylog.note.with(id: "2026-10-20", title: "2026-10-20", kind: "daily")\n\n'
    '= 2026-10-20\n\n'
    r'+ https://www.reddit.com/r/x/google\_releases/'
    '\n'
    '+ https://github.com/VERT-sh/VERT\n'
    '+ https://www.google.com/search?q=x\n';

String _job(String url) =>
    '_system/jobs/articles/${sha1.convert(utf8.encode(url))}.json';

Future<(dynamic, _MemoryStorage)> _mount(WidgetTester tester) async {
  final storage = _MemoryStorage();
  await storage.writeText(_past, _source);
  await storage.writeText(
    'articles/vert.typ',
    '#import "/_system/tylog.typ" as tylog\n\n'
        '#show: tylog.note.with(id: "vert", title: "VERT file converter", kind: "article")\n',
  );
  await tester.pumpWidget(
    const MaterialApp(home: HomeScreen(startup: _emptyStartup)),
  );
  await tester.pumpAndSettle();
  final dynamic home = tester.state(find.byType(HomeScreen));
  home.workspace.vault = Vault.withStorage(storage);
  home.workspace.index = VaultIndex(
    notesByPath: {
      _past: NoteRef(
        id: '2026-10-20',
        path: _past,
        title: '2026-10-20',
        kind: 'daily',
        outgoingLinks: const [],
      ),
      'articles/vert.typ': NoteRef(
        id: 'vert',
        path: 'articles/vert.typ',
        title: 'VERT file converter',
        kind: 'article',
        outgoingLinks: const [],
      ),
    },
    backlinksByTarget: const {},
  );
  home.workspace.replaceNote(_past, _source);
  home.sourceController.text = _source;
  home.richController.loadSource(_source);
  home.workspace.notifyListeners();
  await tester.pumpAndSettle();
  return (home, storage);
}

void main() {
  testWidgets('Save links as articles queues bare links with their day', (
    tester,
  ) async {
    final (home, storage) = await _mount(tester);
    await home.saveLinksAsArticlesForTesting();
    await tester.pumpAndSettle();
    final job =
        jsonDecode(
              await storage.readText(
                _job('https://www.reddit.com/r/x/google_releases/'),
              ),
            )
            as Map;
    expect(job['status'], 'queued');
    expect(job['origin'], _past);
    expect(
      await storage.exists(_job('https://www.google.com/search?q=x')),
      isFalse,
    );
    expect(find.textContaining('2 links queued as articles'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('a done article replaces its bare link in a past day', (
    tester,
  ) async {
    final (home, storage) = await _mount(tester);
    await storage.writeText(
      _job('https://github.com/VERT-sh/VERT'),
      jsonEncode({
        'url': 'https://github.com/VERT-sh/VERT',
        'status': 'done',
        'origin': _past,
        'note_path': 'articles/vert.typ',
      }),
    );
    expect(await home.relinkArticlesForTesting(), 1);
    await tester.pumpAndSettle();
    expect(
      home.workspace.source,
      contains('+ #tylog.ref-note("vert")[VERT file converter]\n'),
    );
    expect(home.workspace.source, contains(r'google\_releases'));
    expect(await home.relinkArticlesForTesting(), 0);
    await tester.pumpWidget(const SizedBox());
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));
}

class _MemoryStorage extends VaultStorage {
  final Map<String, Uint8List> _files = {};
  final Set<String> _directories = {''};

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
  Future<Uint8List> readBytes(String path) async => _files[path]!;

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
