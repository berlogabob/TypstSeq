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
  String shown = '',
}) async {
  final storage = _MemoryStorage();
  await storage.writeText('$enrichShownDir/dev1.jsonl', shown);
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
  await _pump(tester);
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
  await _pump(tester);
  expect(find.byType(EnrichReview), findsNothing);
  expect(find.byKey(const ValueKey('enrich-day-chip')), findsOneWidget);
  await _openIncoming(tester);
  return (home, storage);
}

Future<void> _pump(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.runAsync(() async {});
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _openIncoming(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('enrich-day-chip')));
  await _pump(tester);
}

void main() {
  // flutter test reports Android unless told otherwise; desktop writes blocks.
  final desktop = TargetPlatformVariant.only(TargetPlatform.macOS);
  final phone = TargetPlatformVariant.only(TargetPlatform.android);
  testWidgets('day note gets its block and a Incoming; accept learns', (
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
    await tester.tap(find.text('katiazhavoronkova'));
    await _pump(tester);
    final ledger = await storage.readText('$enrichFeedbackDir/dev1.jsonl');
    expect(jsonDecode(ledger.trim()), containsPair('decision', 'accept'));
    expect(storage.appended['$enrichFeedbackDir/dev1.jsonl'], [ledger]);
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

  testWidgets('ignore records a durable decision without changing note text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1100, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final (home, storage) = await _mount(tester);
    final before = home.workspace.source as String;
    await tester.tap(find.byKey(const ValueKey('enrich-review-Катя')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Not a person/ignore'));
    await _pump(tester);
    final events = EnrichFeedback.parseLedger(
      await storage.readText('$enrichFeedbackDir/dev1.jsonl'),
    );
    expect(events.single.entity, 'mention:ignore');
    expect(events.single.accepted, isFalse);
    expect(
      stripAutoEntities(home.workspace.source as String).trim(),
      stripAutoEntities(before).trim(),
    );
    expect(find.byKey(const ValueKey('enrich-review-Катя')), findsNothing);
    await tester.pumpWidget(const SizedBox());
  }, variant: phone);

  testWidgets('offers are shown once across refreshes and ledger reloads', (
    tester,
  ) async {
    final (_, storage) = await _mount(tester);
    Future<List<EnrichFeedback>> shown() async => EnrichFeedback.parseLedger(
      await storage.readText('$enrichShownDir/dev1.jsonl'),
    );
    final events = await shown();
    expect(
      events.map((e) => (e.surface, e.entity)),
      unorderedEquals([
        ('Катя', 'kz'),
        ('Рома', ''),
        ('Катя приехала, обсудили IADE.', 'marker:fx'),
      ]),
    );
    expect(events.every((e) => e.note == _dayPath && e.shown), isTrue);
    expect(await storage.exists('$enrichFeedbackDir/dev1.jsonl'), isFalse);
    // A tap recomputes the view without re-logging the remaining offers.
    await tester.tap(find.byKey(const ValueKey('enrich-review-Катя')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('katiazhavoronkova'));
    await _pump(tester);
    expect(await shown(), hasLength(3));
    final feedback = await storage.readText('$enrichFeedbackDir/dev1.jsonl');
    expect(jsonDecode(feedback.trim()), containsPair('decision', 'accept'));
    expect(feedback, isNot(contains('"decision":"shown"')));
    final ledger = events.map((e) => jsonEncode(e)).join('\n');
    await tester.pumpWidget(const SizedBox());
    await _mount(tester, shown: ledger);
    await _pump(tester);
    // This is a fresh session whose note still contains all the offers.
    final dynamic fresh = tester.state(find.byType(HomeScreen));
    final freshLedger = await (fresh.workspace.vault as Vault).storage.readText(
      '$enrichShownDir/dev1.jsonl',
    );
    expect(EnrichFeedback.parseLedger(freshLedger), hasLength(3));
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
    await _pump(tester);
    expect(home.workspace.source, isNot(contains('#tylog.tag("design")')));
    expect(home.workspace.source, contains('#tylog.ref-note("iade")[IADE]'));
    final ledger = await storage.readText('$enrichFeedbackDir/dev1.jsonl');
    expect(jsonDecode(ledger.trim()), containsPair('entity', 'tag:design'));
    expect(find.byKey(const ValueKey('enrich-tag-design')), findsNothing);
    await tester.pumpWidget(const SizedBox());
  }, variant: desktop);

  testWidgets('a phone writes only on a tap', (tester) async {
    final (home, storage) = await _mount(tester);
    expect(home.workspace.source, _day);
    expect(await storage.readText(_dayPath), _day);
    expect(find.byKey(const ValueKey('enrich-review-Катя')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('enrich-review-Катя')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('katiazhavoronkova'));
    await _pump(tester);
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
    await tester.tap(find.text('katiazhavoronkova'));
    await _pump(tester);
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
    await _pump(tester);
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
    await _pump(tester);
    await tester.tap(find.byKey(const ValueKey('enrich-tag-remove')));
    await _pump(tester);
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
    await tester.pumpAndSettle();
    final candidate = find.text('katiazhavoronkova');
    await tester.tap(candidate);
    await tester.tap(candidate, warnIfMissed: false);
    await _pump(tester);
    final ledger = await storage.readText('$enrichFeedbackDir/dev1.jsonl');
    expect(
      ledger.trim().split('\n').where((l) => l.contains('"kz"')),
      hasLength(1),
    );
    await tester.pumpWidget(const SizedBox());
  }, variant: desktop);

  testWidgets('day chip opens Incoming filtered to that day', (tester) async {
    await _mount(tester);
    expect(find.text('Incoming'), findsOneWidget);
    expect(find.text('2026-10-22'), findsWidgets);
    expect(find.byType(EnrichReview), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  }, variant: desktop);

  testWidgets(
    'Incoming groups all days newest first and acts on the selected day',
    (tester) async {
      final (home, storage) = await _mount(tester);
      const older = 'daily/2026/10/2026-10-21.typ';
      await tester.runAsync(() async {
        await storage.writeText(older, _day);
        final data =
            jsonDecode(await storage.readText(enrichMentionsPath(_dayPath)))
                as Map;
        data['note'] = older;
        await storage.writeText(enrichMentionsPath(older), jsonEncode(data));
      });
      final oldIndex = home.workspace.index as VaultIndex;
      home.workspace.index = VaultIndex(
        notesByPath: {
          ...oldIndex.notesByPath,
          older: _note('2026-10-21', older, '2026-10-21', 'daily'),
        },
        backlinksByTarget: const {},
      );
      // The chip's sheet stays filtered even if another day has suggestions.
      Navigator.of(tester.element(find.byType(EnrichReview).first)).pop();
      await _pump(tester);
      await _openIncoming(tester);
      expect(find.text('2026-10-21'), findsNothing);
      Navigator.of(tester.element(find.byType(EnrichReview).first)).pop();
      await _pump(tester);
      await tester.tap(find.textContaining('More').first);
      await _pump(tester);
      await tester.tap(find.byKey(const ValueKey('incoming-open')));
      await _pump(tester);
      final newest = tester.getTopLeft(find.text('2026-10-22').last).dy;
      final oldest = tester.getTopLeft(find.text('2026-10-21')).dy;
      expect(newest, lessThan(oldest));
      final reviews = find.byKey(const ValueKey('enrich-review-Катя'));
      expect(reviews, findsNWidgets(2));
      await tester.ensureVisible(reviews.last);
      await tester.tap(reviews.last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('katiazhavoronkova'));
      await _pump(tester);
      final olderSource = await tester.runAsync(() => storage.readText(older));
      expect(olderSource, contains('#tylog.ref-note("kz")[Катя]'));
      expect(
        home.workspace.source,
        isNot(contains('#tylog.ref-note("kz")[Катя] приехала')),
      );
      final ledger = await tester.runAsync(
        () => storage.readText('$enrichFeedbackDir/dev1.jsonl'),
      );
      expect(jsonDecode(ledger!.trim()), containsPair('note', older));
      await tester.pumpWidget(const SizedBox());
    },
    variant: desktop,
  );

  testWidgets('audio proposal is accepted into its note and recorded', (
    tester,
  ) async {
    final (home, storage) = await _mount(tester);
    const path = 'notes/audio.typ';
    const source =
        '#import "/_system/tylog.typ" as tylog\n#show: tylog.note.with(id: "audio-id", title: "Recording", kind: "audio")\n\n= Recording\n\nFrom: #tylog.ref-note("2026-10-22")[Today]\nFrom: #tylog.ref-note("kz")[Katia]\n';
    await tester.runAsync(() async {
      await storage.writeText(path, source);
      await storage.writeText(
        '_system/enrich/audio/a.json',
        jsonEncode({
          'note': path,
          'items': [
            {
              'id': 'audio:abc',
              'text': 'Send notes',
              'date': '2026-11-06',
              'kind': 'agenda',
            },
            {'id': 'audio:def', 'text': 'Call back', 'kind': 'task'},
          ],
        }),
      );
    });
    final oldIndex = home.workspace.index as VaultIndex;
    home.workspace.index = VaultIndex(
      notesByPath: {
        ...oldIndex.notesByPath,
        path: _note('audio-id', path, 'Recording', 'audio'),
      },
      backlinksByTarget: const {},
    );
    Navigator.of(tester.element(find.byType(EnrichReview).first)).pop();
    await _pump(tester);
    await tester.tap(find.textContaining('More').first);
    await _pump(tester);
    await tester.tap(find.byKey(const ValueKey('incoming-open')));
    await _pump(tester);
    await tester.ensureVisible(find.text('Add to agenda'));
    await tester.tap(find.text('Add to agenda'));
    await _pump(tester);
    final saved = await tester.runAsync(() => storage.readText(path));
    expect(saved, startsWith(source));
    expect(saved, contains('text: "Send notes"'));
    expect(saved, contains('due: "2026-11-06"'));
    expect(saved, contains('assignees: ("kz",)'));
    await tester.runAsync(() async {
      final dir = await Directory.systemTemp.createTemp('audio_proposal_');
      addTearDown(() => dir.delete(recursive: true));
      await Directory('${dir.path}/_system').create();
      await File('typst/tylog/lib.typ').copy('${dir.path}/_system/tylog.typ');
      await File('${dir.path}/audio.typ').writeAsString(saved!);
      final result = await Process.run('typst', [
        'compile',
        '--root',
        dir.path,
        '${dir.path}/audio.typ',
        '${dir.path}/audio.pdf',
      ]);
      expect(result.exitCode, 0, reason: result.stderr.toString());
    });
    final reject = find.byTooltip('Reject audio proposal');
    await tester.ensureVisible(reject);
    await tester.tap(reject);
    await _pump(tester);
    final ledger = await tester.runAsync(
      () => storage.readText('_system/decisions/dev1.jsonl'),
    );
    expect(ledger, contains('"action":"accepted"'));
    expect(ledger, contains('"action":"rejected"'));
    expect(
      await tester.runAsync(() => storage.readText(path)),
      isNot(contains('Call back')),
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
    await _pump(tester);
    expect(home.workspace.source, edited);
    await tester.pumpWidget(const SizedBox());
  }, variant: desktop);
}

class _MemoryStorage extends VaultStorage {
  final Map<String, Uint8List> _files = {};
  final appended = <String, List<String>>{};

  @override
  Future<void> appendBytes(String path, List<int> bytes) async {
    appended.putIfAbsent(path, () => []).add(utf8.decode(bytes));
    await super.appendBytes(path, bytes);
  }

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
