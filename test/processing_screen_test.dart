import 'dart:async';
import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/app_mobile.dart';
import 'package:tylog/audio/processing_policy.dart';
import 'package:tylog/models.dart';
import 'package:tylog/processing_jobs.dart';
import 'package:tylog/vault.dart';
import 'package:tylog/widgets/processing_screen.dart';
import 'package:tylog/widgets/audio_processing_settings.dart';
import 'package:tylog_core/storage.dart';

Future<void> _emptyStartup() async {}

class _Storage extends Fake implements VaultStorage {
  final files = <String, String>{};
  bool unreadable = false;
  bool writeFails = false;
  Completer<void>? readGate;

  void job(String kind, String name, Map<String, Object?> data) =>
      files['_system/jobs/$kind/$name.json'] = jsonEncode(data);

  @override
  Future<bool> exists(String path) async =>
      files.containsKey(path) ||
      files.keys.any((key) => key.startsWith('$path/'));

  @override
  Future<List<VaultStorageEntry>> list({
    String path = '',
    bool recursive = false,
  }) async {
    if (unreadable) throw StateError('Folder unavailable');
    final prefix = path.isEmpty ? '' : '$path/';
    final entries = <String, VaultStorageEntry>{};
    for (final file in files.keys.where((file) => file.startsWith(prefix))) {
      final tail = file.substring(prefix.length);
      final child = recursive ? tail : tail.split('/').first;
      entries['$prefix$child'] = VaultStorageEntry(
        path: '$prefix$child',
        isDirectory: !recursive && tail.contains('/'),
      );
    }
    return entries.values.toList();
  }

  @override
  Future<String> readText(String path) async {
    await readGate?.future;
    return files[path]!;
  }

  @override
  Future<void> writeText(String path, String value) async {
    if (writeFails) throw StateError('Write unavailable');
    files[path] = value;
  }
}

Widget _screen(ProcessingJobs jobs, {ValueChanged<String>? onQueued}) =>
    MaterialApp(
      home: ProcessingScreen(
        jobs: jobs,
        onQueued: onQueued ?? (_) {},
        titleForPath: (path) => path == 'notes/audio.typ' ? 'Interview' : null,
      ),
    );

void main() {
  testWidgets('lists all statuses, times, errors and discovered job kinds', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 1500));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final finishedAt = DateTime.now()
        .subtract(const Duration(hours: 2))
        .toUtc()
        .toIso8601String();
    final storage = _Storage()
      ..job('articles', 'a', {
        'title': 'Shared article',
        'url': 'https://example.org',
        'status': 'queued',
        'shared_at': '2026-11-01T10:00:00Z',
      })
      ..job('transcripts', 'b', {
        'note': 'notes/audio.typ',
        'audio': 'assets/audio.m4a',
        'status': 'processing',
        'requested_at': '2026-11-01T11:00:00Z',
        'processing_at': '2026-11-01T11:01:00Z',
      })
      ..job('translations', 'c', {
        'note': 'notes/audio.typ',
        'target': 'en',
        'status': 'done',
        'finished_at': finishedAt,
      })
      ..job('screenshots', 'd', {
        'title': 'Screenshot',
        'status': 'failed',
        'error': 'OCR server unavailable',
      });
    storage.files['_system/jobs/articles/broken.json'] = '{';
    storage.files['_system/jobs/process-now.json'] = '{}';
    storage.files['_system/jobs/articles/invalid.json'] = '{"status":42}';
    storage.files['_system/jobs/articles/array.json'] = '[]';
    final jobs = ProcessingJobs();
    addTearDown(jobs.dispose);
    await jobs.refresh(storage);
    await tester.pumpWidget(_screen(jobs));
    expect(jobs.jobs, hasLength(4));
    expect(find.text('Shared article'), findsOneWidget);
    expect(find.text('Interview'), findsNWidgets(2));
    expect(find.text('Article · Queued'), findsOneWidget);
    expect(find.text('Transcription · Processing'), findsOneWidget);
    expect(find.text('Translation · EN · Done'), findsOneWidget);
    expect(find.text('screenshots · Failed'), findsOneWidget);
    expect(find.text('OCR server unavailable'), findsOneWidget);
    expect(
      find.text('Added: ${shortStamp('2026-11-01T10:00:00Z')}'),
      findsOneWidget,
    );
    expect(
      find.text('Requested: ${shortStamp('2026-11-01T11:00:00Z')}'),
      findsOneWidget,
    );
    expect(
      find.text('Started: ${shortStamp('2026-11-01T11:01:00Z')}'),
      findsOneWidget,
    );
    expect(find.text('Finished: ${shortStamp(finishedAt)}'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Retry'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final kind in ['transcripts', 'translations', 'articles']) {
    testWidgets('Retry preserves the $kind worker payload and queues it', (
      tester,
    ) async {
      final finishedAt = DateTime.now().toUtc().toIso8601String();
      final storage = _Storage()
        ..job(kind, 'a', {
          'status': 'failed',
          'audio': 'assets/audio.m4a',
          'note': 'notes/audio.typ',
          'url': 'https://example.org',
          'origin': 'daily/today.typ',
          'target': 'pt',
          'source_lang': 'en',
          'source_langs': ['en', 'ru'],
          'engine': 'v2',
          'custom': {'keep': true},
          'error': 'Worker failed',
          'processing_at': finishedAt,
          'finished_at': finishedAt,
        });
      final jobs = ProcessingJobs();
      addTearDown(jobs.dispose);
      await jobs.refresh(storage);
      final path = jobs.jobs.single.path;
      final before = jsonDecode(storage.files[path]!) as Map;
      String? queuedPath;
      await tester.pumpWidget(
        _screen(jobs, onQueued: (path) => queuedPath = path),
      );
      await tester.tap(find.widgetWithText(TextButton, 'Retry'));
      await tester.pumpAndSettle();
      final after = jsonDecode(storage.files[path]!) as Map;
      expect(queuedPath, path);
      expect(after['status'], 'queued');
      final timestamp = kind == 'articles' ? 'shared_at' : 'requested_at';
      expect(DateTime.tryParse(after[timestamp] as String), isNotNull);
      for (final key in [
        'audio',
        'note',
        'url',
        'origin',
        'target',
        'source_lang',
        'source_langs',
        'engine',
        'custom',
      ]) {
        expect(after[key], before[key]);
      }
      expect(after.containsKey('error'), isFalse);
      expect(after.containsKey('finished_at'), isFalse);
      expect(after.containsKey('processing_at'), isFalse);
      expect(jobs.activeCount, 1);
      expect(find.text('Queued — see Processing'), findsOneWidget);
      expect(find.text('Retry'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('Retry re-reads status and preserves a worker claim', (
    tester,
  ) async {
    final storage = _Storage()..job('transcripts', 'a', {'status': 'failed'});
    final jobs = ProcessingJobs();
    addTearDown(jobs.dispose);
    await jobs.refresh(storage);
    await tester.pumpWidget(_screen(jobs));
    storage.job('transcripts', 'a', {'status': 'processing', 'engine': 'v2'});
    final before = Map.of(storage.files);
    await tester.tap(find.widgetWithText(TextButton, 'Retry'));
    await tester.pumpAndSettle();
    expect(storage.files, before);
    expect(find.text('Transcription · Processing'), findsOneWidget);
    expect(find.text('Queued — see Processing'), findsNothing);
  });

  test('orders processing, queued, then finished newest first', () async {
    String iso(Duration ago) =>
        DateTime.now().subtract(ago).toUtc().toIso8601String();
    final storage = _Storage()
      ..job('articles', 'done_old', {
        'title': 'done old',
        'status': 'done',
        'finished_at': iso(const Duration(days: 9)),
      })
      ..job('articles', 'failed_new', {
        'title': 'failed new',
        'status': 'failed',
        'finished_at': iso(const Duration(hours: 1)),
      })
      ..job('articles', 'queued_old', {
        'title': 'queued old',
        'status': 'queued',
        'shared_at': iso(const Duration(hours: 5)),
      })
      ..job('articles', 'queued_new', {
        'title': 'queued new',
        'status': 'queued',
        'shared_at': iso(const Duration(minutes: 5)),
      })
      ..job('articles', 'running', {
        'title': 'running',
        'status': 'processing',
        'processing_at': iso(const Duration(days: 30)),
      })
      ..job('articles', 'done_new', {
        'title': 'done new',
        'status': 'done',
        'finished_at': iso(const Duration(hours: 3)),
      });
    final jobs = ProcessingJobs();
    addTearDown(jobs.dispose);
    await jobs.refresh(storage);
    expect(jobs.jobs.map((job) => job.title).toList(), [
      'running',
      'queued new',
      'queued old',
      'failed new',
      'done new',
      'done old',
    ]);
  });

  testWidgets('finished jobs older than 3 days fold under Older (N)', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 1500));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    String iso(Duration ago) =>
        DateTime.now().subtract(ago).toUtc().toIso8601String();
    final storage = _Storage()
      ..job('articles', 'live', {
        'title': 'Live queued',
        'status': 'queued',
        'shared_at': iso(const Duration(minutes: 1)),
      })
      ..job('articles', 'recent', {
        'title': 'Recent done',
        'status': 'done',
        'finished_at': iso(const Duration(days: 1)),
      })
      ..job('articles', 'stale_failed', {
        'title': 'Stale failed',
        'status': 'failed',
        'error': 'Old worker error',
        'finished_at': iso(const Duration(days: 5)),
      })
      ..job('articles', 'stale_done', {
        'title': 'Stale done',
        'status': 'done',
        'finished_at': iso(const Duration(days: 10)),
      });
    final jobs = ProcessingJobs();
    addTearDown(jobs.dispose);
    await jobs.refresh(storage);
    await tester.pumpWidget(_screen(jobs));
    expect(find.text('Live queued'), findsOneWidget);
    expect(find.text('Recent done'), findsOneWidget);
    expect(find.text('Older (2)'), findsOneWidget);
    expect(find.text('Stale failed'), findsNothing);
    expect(find.text('Stale done'), findsNothing);
    await tester.tap(find.text('Older (2)'));
    await tester.pumpAndSettle();
    expect(find.text('Stale failed'), findsOneWidget);
    expect(find.text('Stale done'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Retry'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('empty state, read failure and refresh recovery', (tester) async {
    final storage = _Storage();
    final jobs = ProcessingJobs();
    addTearDown(jobs.dispose);
    await jobs.refresh(storage);
    await tester.pumpWidget(_screen(jobs));
    expect(find.text('No processing jobs'), findsOneWidget);
    storage.job('articles', 'a', {'status': 'queued'});
    storage.unreadable = true;
    await tester.tap(find.byTooltip('Refresh processing'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Folder unavailable'), findsOneWidget);
    storage.unreadable = false;
    await tester.tap(find.byTooltip('Refresh processing'));
    await tester.pumpAndSettle();
    expect(find.text('Article · Queued'), findsOneWidget);
  });

  testWidgets('failed retry keeps the job and offers Retry again', (
    tester,
  ) async {
    final storage = _Storage()..job('transcripts', 'a', {'status': 'failed'});
    final jobs = ProcessingJobs();
    addTearDown(jobs.dispose);
    await jobs.refresh(storage);
    await tester.pumpWidget(_screen(jobs));
    storage.writeFails = true;
    await tester.tap(find.widgetWithText(TextButton, 'Retry'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Write unavailable'), findsOneWidget);
    expect(find.text('Transcription · Failed'), findsOneWidget);
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, 'Retry'))
          .onPressed,
      isNotNull,
    );
    expect(jobs.activeCount, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Process now offers the Processing action', (tester) async {
    var requested = false;
    var opened = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: AudioProcessingSettings(
              section: AiSettingsSection.audio,
              read: () async => const AudioPolicy(),
              write: (_) async {},
              processNow: () async => requested = true,
              onOpenProcessing: () => opened = true,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Process now'));
    await tester.tap(find.text('Process now'));
    await tester.pumpAndSettle();
    expect(requested, isTrue);
    expect(find.text('Queued — see Processing'), findsOneWidget);
    await tester.tap(find.widgetWithText(SnackBarAction, 'Processing'));
    expect(opened, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('badge counts active jobs and disappears when jobs finish', (
    tester,
  ) async {
    final storage = _Storage()
      ..job('articles', 'a', {'status': 'queued'})
      ..job('transcripts', 'b', {'status': 'processing'})
      ..job('translations', 'c', {'status': 'failed'});
    final jobs = ProcessingJobs();
    addTearDown(jobs.dispose);
    await jobs.refresh(storage);
    var opened = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ProcessingBadge(jobs: jobs, onOpen: () => opened = true),
        ),
      ),
    );
    expect(find.byTooltip('Processing · 2'), findsOneWidget);
    await tester.tap(find.byType(ActionChip));
    expect(opened, isTrue);
    storage.job('articles', 'a', {'status': 'done'});
    storage.job('transcripts', 'b', {'status': 'done'});
    await jobs.refresh(storage);
    await tester.pumpAndSettle();
    expect(find.byType(ActionChip), findsNothing);
  });

  test('a stale load cannot replace the next vault snapshot', () async {
    final first = _Storage()..job('articles', 'a', {'status': 'queued'});
    final second = _Storage()..job('transcripts', 'b', {'status': 'failed'});
    final jobs = ProcessingJobs();
    addTearDown(jobs.dispose);
    first.readGate = Completer<void>();
    final pending = jobs.refresh(first);
    await jobs.refresh(second);
    first.readGate!.complete();
    await pending;
    expect(jobs.jobs.single.kind, 'transcripts');
    expect(jobs.activeCount, 0);
  });

  test('a stale Retry cannot write the next vault', () async {
    final first = _Storage()..job('transcripts', 'a', {'status': 'failed'});
    final second = _Storage()..job('transcripts', 'a', {'status': 'failed'});
    final jobs = ProcessingJobs();
    addTearDown(jobs.dispose);
    await jobs.refresh(first);
    final oldJob = jobs.jobs.single;
    await jobs.refresh(second);
    final before = Map.of(second.files);
    expect(await jobs.retry(oldJob), isFalse);
    expect(second.files, before);
  });

  testWidgets('More and the badge open Processing; sync revisions refresh it', (
    tester,
  ) async {
    final storage = _Storage()
      ..job('articles', 'a', {'title': 'Shared article', 'status': 'queued'});
    await tester.pumpWidget(
      const MaterialApp(home: HomeScreen(startup: _emptyStartup)),
    );
    await tester.pumpAndSettle();
    final dynamic home = tester.state(find.byType(HomeScreen));
    home.workspace.vault = Vault.withStorage(storage);
    home.workspace.index = const VaultIndex(
      notesByPath: {},
      backlinksByTarget: {},
    );
    home.workspace.notifyListeners();
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Processing · 1'));
    await tester.pumpAndSettle();
    expect(find.byType(ProcessingScreen), findsOneWidget);
    storage.job('articles', 'a', {
      'title': 'Shared article',
      'status': 'processing',
    });
    home.workspace.syncing = true;
    home.workspace.notifyListeners();
    await tester.pumpAndSettle();
    expect(find.text('Article · Processing'), findsOneWidget);
    storage.job('articles', 'a', {'title': 'Shared article', 'status': 'done'});
    home.workspace.syncing = false;
    home.workspace.notifyListeners();
    await tester.pumpAndSettle();
    expect(find.text('Article · Done'), findsOneWidget);
    storage.job('transcripts', 'b', {'title': 'Recording', 'status': 'failed'});
    home.workspace.indexRevision++;
    home.workspace.notifyListeners();
    await tester.pumpAndSettle();
    expect(find.text('Article · Done'), findsOneWidget);
    expect(find.text('Transcription · Failed'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byTooltip('Processing · 1'), findsNothing);
    await tester.tap(find.text('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Processing'));
    await tester.pumpAndSettle();
    expect(find.byType(ProcessingScreen), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
