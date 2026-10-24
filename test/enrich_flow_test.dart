// ignore_for_file: depend_on_referenced_packages
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/app_mobile.dart';
import 'package:tylog/models.dart';
import 'package:tylog/vault.dart';
import 'package:tylog/vault_registry.dart';
import 'package:tylog/vault_storage.dart';
import 'package:tylog/widgets/enrich_review.dart';
import 'package:tylog_core/enrich.dart';

Future<void> _emptyStartup() async {}

const _dayPath = 'daily/2026/10/2026-10-22.typ';
const _day =
    '#import "/_system/tylog.typ" as tylog\n\n'
    '#show: tylog.note.with(id: "2026-10-22", title: "2026-10-22", kind: "daily")\n\n'
    '= 2026-10-22\n\n'
    'Катя приехала, обсудили IADE.\n';

NoteRef _note(
  String id,
  String path,
  String title,
  String kind, {
  List<String> aliases = const [],
}) => NoteRef(
  id: id,
  path: path,
  title: title,
  kind: kind,
  aliases: aliases,
  outgoingLinks: const [],
);

Future<(dynamic, _MemoryStorage)> _mount(
  WidgetTester tester, {
  String dayPath = _dayPath,
}) async {
  final storage = _MemoryStorage();
  await storage.writeText(dayPath, _day);
  await storage.writeText(
    'notes/kz.typ',
    '#import "/_system/tylog.typ" as tylog\n\n'
        '#show: tylog.note.with(id: "kz", title: "katiazhavoronkova", kind: "person")\n',
  );
  await storage.writeText(
    'notes/fixit.typ',
    '#import "/_system/tylog.typ" as tylog\n\n'
        '#show: tylog.note.with(id: "fx", title: "fixit")\n',
  );
  await storage.writeText(
    'notes/iade.typ',
    '#import "/_system/tylog.typ" as tylog\n\n'
        '#show: tylog.note.with(id: "iade", title: "IADE", kind: "organization")\n',
  );
  await storage.writeText(
    'notes/x.typ',
    '#import "/_system/tylog.typ" as tylog\n\n'
        '#show: tylog.note.with(id: "x", title: "x", tags: ("design",))\n',
  );
  await storage.writeText(
    enrichMentionsPath(dayPath),
    jsonEncode({
      'schema': 1,
      'note': dayPath,
      'content_sha': enrichContentSha(_day),
      'mentions': [
        {
          'surface': 'Катя',
          'type': 'person',
          'line': 7,
          'hints': ['Katia'],
        },
        {'surface': 'IADE', 'type': 'organization', 'line': 7},
        {'surface': 'Рома', 'type': 'person', 'line': 7},
      ],
      'keywords': ['design'],
      'markers': [
        {'line': 7, 'marker': 'fx'},
      ],
    }),
  );
  await tester.pumpWidget(
    const MaterialApp(home: HomeScreen(startup: _emptyStartup)),
  );
  await tester.pumpAndSettle();
  final dynamic home = tester.state(find.byType(HomeScreen));
  home.vaultRegistry = VaultRegistry(
    File('${Directory.systemTemp.path}/unused-vaults.json'),
    [],
    '',
    deviceId: 'dev1',
  );
  home.workspace.vault = Vault.withStorage(storage);
  home.workspace.index = VaultIndex(
    notesByPath: {
      dayPath: _note(
        dayPath.split('/').last.replaceFirst('.typ', ''),
        dayPath,
        '2026-10-22',
        'daily',
      ),
      'notes/kz.typ': _note(
        'kz',
        'notes/kz.typ',
        'katiazhavoronkova',
        'person',
      ),
      'notes/iade.typ': _note('iade', 'notes/iade.typ', 'IADE', 'organization'),
      'notes/fixit.typ': _note('fx', 'notes/fixit.typ', 'fixit', 'note'),
      'notes/x.typ': NoteRef(
        id: 'x',
        path: 'notes/x.typ',
        title: 'x',
        tags: const ['design'],
        outgoingLinks: const [],
      ),
    },
    backlinksByTarget: const {},
  );
  home.workspace.replaceNote(dayPath, _day);
  home.sourceController.text = _day;
  home.richController.loadSource(_day);
  home.workspace.notifyListeners();
  await tester.pumpAndSettle();
  return (home, storage);
}

void main() {
  // flutter test reports Android unless told otherwise; desktop writes blocks.
  final desktop = TargetPlatformVariant.only(TargetPlatform.macOS);
  final phone = TargetPlatformVariant.only(TargetPlatform.android);
  testWidgets('day note gets its block and a review strip; accept learns', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1100, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final (home, storage) = await _mount(tester);

    // Exact name: linked in the block, with the existing tag; user text intact.
    final written = home.workspace.source as String;
    expect(written, startsWith(_day.trimRight()));
    expect(
      written,
      contains(
        '$autoEntitiesMarker\n== Mentions\n- #tylog.ref-note("iade")[IADE]',
      ),
    );
    expect(written, contains('#tylog.tag("design")'));
    // Prefix-only nickname: asked, not linked. Unknown person: proposed.
    expect(find.byKey(const ValueKey('enrich-review-Катя')), findsOneWidget);
    expect(find.byKey(const ValueKey('enrich-new-Рома')), findsOneWidget);
    expect(find.byKey(const ValueKey('enrich-linked-IADE')), findsOneWidget);

    expect(find.byKey(const ValueKey('enrich-tag-design')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('enrich-review-Катя')));
    await tester.pumpAndSettle();
    final ledger = await storage.readText('$enrichFeedbackDir/dev1.jsonl');
    expect(jsonDecode(ledger.trim()), containsPair('decision', 'accept'));
    expect(
      home.workspace.source,
      contains('#tylog.ref-note("kz")[Катя] приехала'),
    );
    // Now a link in the user's text: no chip offers to unlink it.
    expect(find.byKey(const ValueKey('enrich-linked-Катя')), findsNothing);
    expect(find.byKey(const ValueKey('enrich-review-Катя')), findsNothing);
    expect(
      await storage.readText('notes/kz.typ'),
      contains('aliases: ("Катя",)'),
    );
    // The worker must not re-extract the note the user just linked.
    final mentions =
        jsonDecode(await storage.readText(enrichMentionsPath(_dayPath))) as Map;
    expect(
      mentions['content_sha'],
      enrichContentSha(home.workspace.source as String),
    );
    await tester.pumpWidget(const SizedBox());
  }, variant: desktop);

  testWidgets('removing a tag chip drops it from the block for good', (
    tester,
  ) async {
    final (home, storage) = await _mount(tester);
    expect(home.workspace.source, contains('#tylog.tag("design")'));
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('enrich-tag-design')),
        matching: find.byIcon(Icons.close),
      ),
    );
    await tester.pumpAndSettle();
    expect(home.workspace.source, isNot(contains('#tylog.tag("design")')));
    expect(home.workspace.source, contains('#tylog.ref-note("iade")[IADE]'));
    final ledger = await storage.readText('$enrichFeedbackDir/dev1.jsonl');
    expect(jsonDecode(ledger.trim()), containsPair('entity', 'tag:design'));
    expect(find.byKey(const ValueKey('enrich-tag-design')), findsNothing);
    await tester.pumpWidget(const SizedBox());
  }, variant: desktop);

  testWidgets('a phone shows the strip but writes only on a tap', (
    tester,
  ) async {
    final (home, storage) = await _mount(tester);
    expect(home.workspace.source, _day);
    expect(await storage.readText(_dayPath), _day);
    expect(find.byKey(const ValueKey('enrich-review-Катя')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('enrich-review-Катя')));
    await tester.pumpAndSettle();
    expect(home.workspace.source, contains('#tylog.ref-note("kz")[Катя]'));
    expect(home.workspace.source, contains(autoEntitiesMarker));
    await tester.pumpWidget(const SizedBox());
  }, variant: phone);

  testWidgets('today is not auto-written; a tap still writes', (tester) async {
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final today =
        'daily/${now.year}/${two(now.month)}/'
        '${now.year}-${two(now.month)}-${two(now.day)}.typ';
    final (home, _) = await _mount(tester, dayPath: today);
    expect(home.workspace.source, _day);
    expect(find.byKey(const ValueKey('enrich-review-Катя')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('enrich-review-Катя')));
    await tester.pumpAndSettle();
    expect(home.workspace.source, contains(autoEntitiesMarker));
    await tester.pumpWidget(const SizedBox());
  }, variant: desktop);

  testWidgets('a fixit chip files the line under fixit and learns', (
    tester,
  ) async {
    final (home, storage) = await _mount(tester);
    final chip = find.byKey(const ValueKey('enrich-marker-fx-7'));
    expect(chip, findsOneWidget);
    await tester.tap(chip);
    await tester.pumpAndSettle();
    expect(
      home.workspace.source,
      contains('#tylog.ref-note("fx")[fixit] Катя приехала'),
    );
    final ledger = await storage.readText('$enrichFeedbackDir/dev1.jsonl');
    expect(jsonDecode(ledger.trim()), containsPair('entity', 'marker:fx'));
    expect(find.byKey(const ValueKey('enrich-marker-fx-7')), findsNothing);
    final mentions =
        jsonDecode(await storage.readText(enrichMentionsPath(_dayPath))) as Map;
    expect(
      mentions['content_sha'],
      enrichContentSha(home.workspace.source as String),
    );
    await tester.pumpWidget(const SizedBox());
  }, variant: desktop);

  testWidgets('tapping the tag word offers removal too', (tester) async {
    final (home, storage) = await _mount(tester);
    await tester.tap(find.byKey(const ValueKey('enrich-tag-design')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('enrich-tag-remove')));
    await tester.pumpAndSettle();
    expect(home.workspace.source, isNot(contains('#tylog.tag("design")')));
    expect(
      await storage.readText('$enrichFeedbackDir/dev1.jsonl'),
      contains('tag:design'),
    );
    await tester.pumpWidget(const SizedBox());
  }, variant: desktop);

  testWidgets('one decision at a time: a double tap records one accept', (
    tester,
  ) async {
    final (home, storage) = await _mount(tester);
    final chip = find.byKey(const ValueKey('enrich-review-Катя'));
    await tester.tap(chip);
    await tester.tap(chip, warnIfMissed: false);
    await tester.pumpAndSettle();
    final ledger = await storage.readText('$enrichFeedbackDir/dev1.jsonl');
    expect(
      ledger.trim().split('\n').where((l) => l.contains('"kz"')),
      hasLength(1),
    );
    await tester.pumpWidget(const SizedBox());
  }, variant: desktop);

  testWidgets('on a phone-width screen the strip stays a fifth of the height', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _mount(tester);
    expect(find.byType(EnrichReview), findsOneWidget);
    expect(
      tester.getSize(find.byType(EnrichReview)).height,
      lessThanOrEqualTo(160),
    );
    await tester.pumpWidget(const SizedBox());
  }, variant: desktop);

  testWidgets('a note edited since extraction is left alone', (tester) async {
    final (home, storage) = await _mount(tester);
    expect(home.workspace.source, contains(autoEntitiesMarker));
    const edited = '$_day\nnew line\n';
    await storage.writeText(_dayPath, edited);
    home.workspace.replaceNote(_dayPath, edited);
    home.workspace.notifyListeners();
    await tester.pumpAndSettle();
    expect(home.workspace.source, edited);
    await tester.pumpWidget(const SizedBox());
  }, variant: desktop);
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
  Future<void> delete(String path) async {
    _files.removeWhere((key, _) => key == path || key.startsWith('$path/'));
  }

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
