import 'dart:convert';
import 'dart:io';
import 'package:drift/native.dart';
import 'package:tylog_core/storage.dart';
import 'package:tylog/database/tylog_database.dart';
import 'package:tylog/database/note_persistence.dart';
import 'package:tylog/retrieval/note_chunk_sync.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/models.dart';
import 'package:tylog/month_calendar.dart';
import 'package:tylog/nextcloud_sync.dart';
import 'package:tylog/screenshots_ocr.dart';
import 'package:tylog/vault_registry.dart';
import 'package:tylog/widgets/property_select_chip.dart';
import 'package:tylog/widgets/screenshot_strip.dart';
import 'package:tylog/widgets/screenshots_settings.dart';
import 'package:tylog/widgets/work_surface.dart';

const shot = NoteRef(
  id: 'shot-0123456789abcdef',
  path: 'screenshots/2026/10/shot-0123456789abcdef.typ',
  title: 'Saved screen',
  kind: 'screenshot',
  date: '2026-10-04',
  outgoingLinks: [],
  properties: {
    'captured_at': '2026-10-04T09:07:00',
    'status': 'inbox',
    'source_app': 'Browser',
    'keywords': ['flutter'],
  },
);
const kept = NoteRef(
  id: 'shot-fedcba9876543210',
  path: 'screenshots/2026/09/shot-fedcba9876543210.typ',
  title: 'Kept screen',
  kind: 'screenshot',
  date: '2026-09-03',
  outgoingLinks: [],
  properties: {'status': 'kept', 'source_app': 'Editor'},
);
const article = NoteRef(
  id: 'article',
  path: 'articles/a.typ',
  title: 'Article',
  kind: 'article',
  date: '2026-10-04',
  outgoingLinks: [],
);
VaultIndex get index => VaultIndex(
  notesByPath: {
    for (final n in [shot, kept, article]) n.path: n,
  },
  backlinksByTarget: const {},
  tasks: const [],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('phone request writes only syncable system state', () async {
    final dir = await Directory.systemTemp.createTemp('screenshots-request-');
    addTearDown(() => dir.delete(recursive: true));
    final storage = LocalVaultStorage(dir);
    await storage.writeText('daily/2026/10/2026-10-04.typ', 'original daily');
    await requestScreenshotsRun(storage, now: DateTime.utc(2026, 10, 4, 12));
    expect(
      jsonDecode(
        await storage.readText('_system/screenshots/run-request.json'),
      ),
      {'requested_at': '2026-10-04T12:00:00.000Z'},
    );
    expect(
      await storage.readText('daily/2026/10/2026-10-04.typ'),
      'original daily',
    );
    expect(
      (await storage.list(recursive: true)).where((e) => !e.isDirectory),
      hasLength(2),
    );
  });
  test(
    'OCR text and keywords reach FTS and semantic chunks through ordinary notes',
    () async {
      final db = TyLogDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      const source =
          '#show: tylog.note.with(id: "shot-0123456789abcdef", title: "Saved screen", kind: "screenshot", date: "2026-10-04", properties: (status: "inbox", keywords: ("quasar",)))\nOCR nebula';
      final saved = await persistVaultNote(
        db,
        path: shot.path,
        source: source,
        nowMs: 1,
      );
      expect(await db.searchNodeIds('nebula'), [shot.id]);
      expect(await db.searchNodeIds('quasar'), [shot.id]);
      await syncNoteChunks(db, {
        shot.path: (title: saved.node.title, text: saved.node.content),
      });
      final chunks = await db.pendingChunks();
      expect(chunks, isNotEmpty);
      expect(chunks.map((c) => c.content).join(' '), contains('nebula'));
      expect(chunks.map((c) => c.content).join(' '), contains('quasar'));
    },
  );
  test('screenshot stages and asset path use the producer contract', () {
    expect(screenshotStatusOptions, ['inbox', 'kept', 'acted', 'archived']);
    expect(screenshotStatusStage(null), 'inbox');
    expect(screenshotStatusStage('read'), 'inbox');
    expect(screenshotStatusStage('acted'), 'acted');
    expect(
      screenshotAssetPath(shot),
      'assets/screenshots/2026/10/shot-0123456789abcdef.webp',
    );
    expect(screenshotAssetPath(article), isNull);
    expect(standardNoteKinds, contains('screenshot'));
    expect(screenshotsOnDay(index, '2026-10-04'), [shot]);
    expect(isSyncableVaultPath(shot.path), isTrue);
    expect(isSyncableVaultPath('_system/screenshots/status.json'), isTrue);
    expect(isSyncableVaultPath('_system/screenshots/run-request.json'), isTrue);
  });
  test('day screenshots sort by captured time with missing dates last', () {
    final early = NoteRef(
      id: 'early',
      path: 'early',
      title: 'Early',
      kind: 'screenshot',
      date: shot.date,
      outgoingLinks: const [],
      properties: const {'captured_at': '2026-10-04T08:00:00'},
    );
    final missing = NoteRef(
      id: 'missing',
      path: 'missing',
      title: 'Missing',
      kind: 'screenshot',
      date: shot.date,
      outgoingLinks: const [],
      properties: const {'captured_at': 'invalid'},
    );
    final ordered = screenshotsOnDay(
      VaultIndex(
        notesByPath: {
          missing.path: missing,
          shot.path: shot,
          early.path: early,
        },
        backlinksByTarget: const {},
        tasks: const [],
      ),
      shot.date!,
    );
    expect(ordered, [early, shot, missing]);
  });
  test('launchd watch and schedule arguments, XML escaping, validation', () {
    final watch = screenshotLaunchAgentPlist(
      home: '/Users/A&B',
      vault: '/vault <one>',
      mode: 'watch',
    );
    expect(watch, contains('/opt/homebrew/bin/uv'));
    expect(watch, contains('A&amp;B/Nextcloud/InstantUpload/Screenshots'));
    expect(
      watch,
      contains('<string>ollama_ocr.py</string><string>--watch</string>'),
    );
    expect(watch, contains('<key>KeepAlive</key><true/>'));
    expect(watch, isNot(contains('StartCalendarInterval')));
    final scheduled = screenshotLaunchAgentPlist(
      home: '/Users/me',
      vault: '/vault <one>',
      mode: 'schedule',
      time: '22:17',
    );
    expect(
      scheduled,
      contains(
        '<string>backfill.py</string><string>--vault</string><string>/vault &lt;one&gt;</string>',
      ),
    );
    expect(scheduled, contains('<key>Hour</key><integer>22</integer>'));
    expect(scheduled, contains('<key>Minute</key><integer>17</integer>'));
    expect(scheduled, isNot(contains('KeepAlive')));
    expect(
      () => screenshotLaunchAgentPlist(
        home: '/u',
        vault: '/v',
        mode: 'schedule',
        time: '24:60',
      ),
      throwsArgumentError,
    );
    expect(
      () =>
          screenshotLaunchAgentPlist(home: '/u', vault: '/v', mode: 'invalid'),
      throwsArgumentError,
    );
  });
  test(
    'registry persists and loads OCR mode and schedule with PDF settings',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'screenshots-settings-',
      );
      addTearDown(() => dir.delete(recursive: true));
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (_) async => dir.path,
          );
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              const MethodChannel('plugins.flutter.io/path_provider'),
              null,
            ),
      );
      final registry = VaultRegistry(File('${dir.path}/vaults.json'), [
        VaultEntry(id: 'vault', name: 'Vault', path: dir.path),
      ], 'vault');
      await registry.setPdfPaper('a5');
      await registry.setScreenshotsOcr('schedule', '19:45');
      final loaded = await VaultRegistry.load();
      expect(loaded.screenshotsMode, 'schedule');
      expect(loaded.screenshotsTime, '19:45');
      expect(loaded.pdfPaper, 'a5');
    },
  );
  testWidgets(
    'day strip reads assets and opens screenshot without daily writes',
    (tester) async {
      final dir = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('screenshots-day-'),
      ))!;
      addTearDown(() => tester.runAsync(() => dir.delete(recursive: true)));
      final daily = File('${dir.path}/daily.typ');
      await tester.runAsync(() => daily.writeAsString('unchanged daily'));
      final opened = <String>[];
      final reads = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ScreenshotStrip(
              index: index,
              day: '2026-10-04',
              onOpenPath: opened.add,
              imageResolver: (path) async {
                reads.add(path);
                return null;
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Screenshots (1)'), findsOneWidget);
      expect(find.text('09:07'), findsOneWidget);
      expect(find.text('Kept screen'), findsNothing);
      await tester.tap(find.text('Saved screen'));
      expect(opened, [shot.path]);
      expect(reads, contains(screenshotAssetPath(shot)));
      expect(await tester.runAsync(daily.readAsString), 'unchanged daily');
    },
  );
  testWidgets('calendar marks screenshot days without a daily or backlink', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 350,
            child: MonthCalendar(
              dayMarks: (daily: <String>{}, refs: <String>{}),
              screenshotDays: const {'2026-10-04'},
              initialMonth: DateTime(2026, 10),
              onOpenDay: (_) {},
            ),
          ),
        ),
      ),
    );
    expect(
      find.byKey(const Key('screenshot-marker-2026-10-04')),
      findsOneWidget,
    );
  });
  testWidgets('screenshot shelf groups, filters, searches and updates triage', (
    tester,
  ) async {
    final statuses = <String>[];
    final ratings = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LibraryView(
            index: index,
            calendar: const [],
            dayMarks: (daily: <String>{}, refs: <String>{}),
            progressByPath: const {},
            onOpenPath: (_) {},
            onOpenDay: (_) {},
            onSetTaskStatus: (_, _) async {},
            onSetReadStatus: (n, s) async => statuses.add('${n.id}:$s'),
            onSetRelevance: (n, r) async => ratings.add('${n.id}:$r'),
            onCreateNote: (_) {},
            onCreateEntity: () {},
            onImportMarkdownArticles: () async {},
            onReadPath: (_) {},
            onDeleteArticle: (_) async {},
          ),
        ),
      ),
    );
    await tester.tap(find.text('Screenshots'));
    await tester.pumpAndSettle();
    expect(find.text('All · 2'), findsOneWidget);
    expect(find.text('Browser · 1'), findsOneWidget);
    expect(find.text('Editor · 1'), findsOneWidget);
    expect(find.text('Inbox · 1'), findsOneWidget);
    expect(find.text('Article'), findsNothing);
    expect(find.text('Import Markdown articles'), findsNothing);
    expect(find.byType(ScreenshotThumbnail), findsWidgets);
    await tester.tap(find.text('Inbox · 1'));
    await tester.pumpAndSettle();
    expect(find.text('Kept screen'), findsNothing);
    await tester.longPress(find.text('Saved screen'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(PropertySelectChip, 'Inbox'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Acted'));
    await tester.pumpAndSettle();
    expect(statuses, ['${shot.id}:acted']);
    await tester.tap(find.byTooltip('Screenshot actions').first);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(PropertySelectChip, '★'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('High').last);
    await tester.pumpAndSettle();
    expect(ratings, ['${shot.id}:high']);
    await tester.tap(find.byKey(const Key('screenshots-group')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Group by month'));
    await tester.pumpAndSettle();
    expect(find.text('2026-10 · 1'), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('screenshots-search')),
      'flutter',
    );
    await tester.pumpAndSettle();
    expect(find.text('Saved screen'), findsOneWidget);
  });
  testWidgets('phone OCR controls are read-only but Process now works', (
    tester,
  ) async {
    var requests = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ScreenshotsSettings(
            mode: 'schedule',
            time: '03:00',
            editable: false,
            onConfigure: (_, _) async =>
                fail('Phone must not configure launchd'),
            onProcessNow: () async {
              requests++;
            },
            readStatus: () async => jsonEncode({
              'last_run': '2026-10-04',
              'processed': 12,
              'errors': 2,
            }),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<DropdownButton<String>>(find.byType(DropdownButton<String>))
          .onChanged,
      isNull,
    );
    expect(find.textContaining('12 processed'), findsOneWidget);
    await tester.tap(find.text('Process now'));
    await tester.pumpAndSettle();
    expect(requests, 1);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'Mac mode callback persists selected schedule and reports missing status',
    (tester) async {
      final configured = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ScreenshotsSettings(
              mode: 'off',
              time: '03:00',
              editable: true,
              onConfigure: (m, t) async => configured.add('$m:$t'),
              onProcessNow: () async {},
              readStatus: () async => throw const FormatException('missing'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('No screenshot status available'), findsOneWidget);
      await tester.tap(find.text('Off'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Schedule').last);
      await tester.pumpAndSettle();
      expect(configured, ['schedule:03:00']);
      expect(find.text('Daily at 03:00'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
