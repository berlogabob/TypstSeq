import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tylog_core/tylog_core.dart';
import 'package:tylog/audio/transcript_jobs.dart';
import 'package:tylog/processing_jobs.dart';

void main() {
  late Directory dir;
  late LocalVaultStorage storage;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('tylog_transcript_jobs_');
    storage = LocalVaultStorage(dir);
    addTearDown(() => dir.delete(recursive: true));
  });

  test(
    'screenshot request uses the worker key and appears in Processing',
    () async {
      const note = 'screenshots/2026/01/shot-old.typ';
      final now = DateTime.utc(2026, 11, 2);
      await enqueueScreenshotTranslation(
        storage,
        notePath: note,
        target: 'ru',
        sourceLang: 'pt',
        now: now,
      );
      expect(await readTranslationJob(storage, note, 'ru'), {
        'note': note,
        'target': 'ru',
        'lang': 'pt',
        'screenshot': true,
        'requested_at': now.toIso8601String(),
        'status': 'queued',
      });
      expect(
        translationJobPath(note, 'ru'),
        isNot(translationJobPath(note, 'en')),
      );
      expect(
        translationJobPath(note, 'ru'),
        '_system/jobs/translations/a58fc74de3b02065769baf0e93d4407487f118f8.json',
      );
      final jobs = await loadProcessingJobs(storage);
      expect(jobs.single.kind, 'translations');
      expect(jobs.single.notePath, note);
      expect(jobs.single.active, isTrue);
    },
  );

  test(
    'screenshot request preserves claimed jobs and retry line provenance',
    () async {
      const note = 'screenshots/shot-old.typ';
      final path = translationJobPath(note, 'en');
      for (final status in ['queued', 'processing', 'done']) {
        final job = jsonEncode({
          'note': note,
          'status': status,
          'claimed_by': 'worker',
        });
        await storage.writeText(path, job);
        await enqueueScreenshotTranslation(
          storage,
          notePath: note,
          target: 'en',
          sourceLang: 'pt',
        );
        expect(await storage.readText(path), job);
      }
      const lines = [
        {'text': 'My correction', 'status': 'user'},
      ];
      await storage.writeText(
        path,
        jsonEncode({
          'note': note,
          'status': 'failed',
          'auto': true,
          'error': 'failure',
          'processing_at': 'old',
          'lines': lines,
        }),
      );
      await enqueueScreenshotTranslation(
        storage,
        notePath: note,
        target: 'en',
        sourceLang: 'pt',
      );
      final job = (await readTranslationJob(storage, note, 'en'))!;
      expect(job['status'], 'queued');
      expect(job['lines'], lines);
      expect(job.containsKey('auto'), isFalse);
      expect(job.containsKey('error'), isFalse);
      expect(job.containsKey('processing_at'), isFalse);
    },
  );

  test(
    'enqueueTranscript writes a queued JSON job and transcriptJobStatus reads it',
    () async {
      const audio = '/assets/clips/voice.mp3';
      const note = '/notes/voice.typ';

      await enqueueTranscript(storage, audioPath: audio, notePath: note);

      final path = transcriptJobPath(audio);
      expect(path, endsWith('.json'));
      expect(await storage.exists(path), isTrue);

      final data =
          jsonDecode(await storage.readText(path)) as Map<String, dynamic>;
      expect(data['status'], 'queued');
      expect(data['audio'], audio);
      expect(data['note'], note);

      expect(await transcriptJobStatus(storage, audio), 'queued');
    },
  );

  test(
    'a second enqueue does not overwrite a job whose status changed to processing',
    () async {
      const audio = '/assets/clips/voice.mp3';
      const note = '/notes/voice.typ';

      await enqueueTranscript(storage, audioPath: audio, notePath: note);

      final path = transcriptJobPath(audio);
      await storage.writeText(
        path,
        jsonEncode({'audio': audio, 'note': note, 'status': 'processing'}),
      );

      await enqueueTranscript(storage, audioPath: audio, notePath: note);

      final data =
          jsonDecode(await storage.readText(path)) as Map<String, dynamic>;
      expect(data['status'], 'processing');
      expect(await transcriptJobStatus(storage, audio), 'processing');
    },
  );

  test('a job with status failed is queued again', () async {
    const audio = '/assets/clips/voice.mp3';
    const note = '/notes/voice.typ';

    await enqueueTranscript(storage, audioPath: audio, notePath: note);

    final path = transcriptJobPath(audio);
    await storage.writeText(
      path,
      jsonEncode({'audio': audio, 'note': note, 'status': 'failed'}),
    );

    await enqueueTranscript(storage, audioPath: audio, notePath: note);

    final data =
        jsonDecode(await storage.readText(path)) as Map<String, dynamic>;
    expect(data['status'], 'queued');
    expect(await transcriptJobStatus(storage, audio), 'queued');
  });

  test('a done job is queued again only with retryDone', () async {
    const audio = '/assets/clips/voice.mp3';
    const note = '/notes/voice.typ';
    await storage.createDirectory('_system/jobs/transcripts');
    await storage.writeText(
      transcriptJobPath(audio),
      jsonEncode({'audio': audio, 'note': note, 'status': 'done'}),
    );

    await enqueueTranscript(storage, audioPath: audio, notePath: note);
    expect(await transcriptJobStatus(storage, audio), 'done');

    await enqueueTranscript(
      storage,
      audioPath: audio,
      notePath: note,
      retryDone: true,
    );
    expect(await transcriptJobStatus(storage, audio), 'queued');
  });

  test('re-process keeps note edits and the worker sidecar intact', () async {
    const audio = 'assets/clips/voice.mp3';
    const note = 'notes/voice.typ';
    const source =
        '== Transcript\n- 00:01 My correction\n'
        '== Translation ru\n- 00:01 Моя правка\n'
        '== Comments\n- 00:02 My comment\n'
        '== Context\nMy programme\n';
    final path = transcriptJobPath(audio);
    final sidecar = path.replaceFirst('/transcripts/', '/segments/');
    const sidecarText = '{"lines":[{"text":"My correction","status":"user"}]}';
    await storage.writeText(note, source);
    await storage.writeText(sidecar, sidecarText);
    await storage.writeText(
      path,
      jsonEncode({
        'audio': audio,
        'note': note,
        'status': 'done',
        'lang': 'pt',
      }),
    );
    final before = await storage.readBytes(note);
    final now = DateTime.utc(2026, 10, 31, 12);

    await enqueueTranscript(
      storage,
      audioPath: audio,
      notePath: note,
      now: now,
      retryDone: true,
    );

    expect(jsonDecode(await storage.readText(path)), {
      'audio': audio,
      'note': note,
      'requested_at': now.toIso8601String(),
      'status': 'queued',
    });
    expect(await storage.readBytes(note), before);
    expect(await storage.readText(sidecar), sidecarText);
  });

  test('re-process does not reset a queued or claimed job', () async {
    const audio = 'assets/clips/voice.mp3';
    final path = transcriptJobPath(audio);
    for (final status in ['queued', 'processing']) {
      final job = jsonEncode({
        'audio': audio,
        'note': 'notes/voice.typ',
        'status': status,
        'claimed_by': 'worker',
      });
      await storage.writeText(path, job);
      await enqueueTranscript(
        storage,
        audioPath: audio,
        notePath: 'notes/voice.typ',
        retryDone: true,
      );
      expect(await storage.readText(path), job);
    }
  });

  test(
    'transcriptJobStatus is null when no job exists and transcriptJobPath is stable',
    () async {
      expect(
        await transcriptJobStatus(storage, '/assets/clips/missing.mp3'),
        isNull,
      );

      const audio = '/assets/clips/voice.mp3';
      expect(transcriptJobPath(audio), transcriptJobPath(audio));
      expect(transcriptJobPath(audio), endsWith('.json'));
    },
  );

  test(
    'transcript languages prefer the list and fall back to the old lang',
    () async {
      const audio = 'assets/mixed.m4a';
      expect(await transcriptJobLangs(storage, audio), isEmpty);
      await storage.createDirectory('_system/jobs/transcripts');
      for (final (job, expected) in <(Map<String, Object?>, List<String>)>[
        (
          {
            'langs': ['ru', 'en', 'pt'],
            'lang': 'ru',
          },
          ['ru', 'en', 'pt'],
        ),
        ({'langs': [], 'lang': 'ru'}, []),
        ({'lang': 'pt'}, ['pt']),
        ({}, []),
        (
          {
            'langs': ['en', 7],
          },
          ['en'],
        ),
      ]) {
        await storage.writeText(transcriptJobPath(audio), jsonEncode(job));
        expect(await transcriptJobLangs(storage, audio), expected);
      }
    },
  );

  test('translation jobs include all source languages when supplied', () async {
    const audio = 'assets/mixed.m4a';
    await enqueueTranslation(
      storage,
      audioPath: audio,
      notePath: 'notes/mixed.typ',
      target: 'pt',
      sourceLang: 'ru',
      sourceLangs: ['ru', 'en', 'pt'],
    );
    final job =
        jsonDecode(await storage.readText(translationJobPath(audio, 'pt')))
            as Map;
    expect(job['source_lang'], 'ru');
    expect(job['source_langs'], ['ru', 'en', 'pt']);
  });

  test(
    'translation jobs queue once per target and report the language',
    () async {
      const audio = 'assets/a.m4a';
      await enqueueTranslation(
        storage,
        audioPath: audio,
        notePath: 'notes/a.typ',
        target: 'ru',
        sourceLang: 'pt',
      );
      expect(await translationJobStatus(storage, audio, 'ru'), 'queued');
      expect(await translationJobStatus(storage, audio, 'en'), isNull);
      expect(
        translationJobPath(audio, 'ru'),
        isNot(translationJobPath(audio, 'en')),
      );
      final job =
          jsonDecode(await storage.readText(translationJobPath(audio, 'ru')))
              as Map;
      expect(job['source_lang'], 'pt');
      expect(job.containsKey('source_langs'), isFalse);

      await storage.writeText(
        transcriptJobPath(audio),
        jsonEncode({'status': 'done', 'lang': 'pt'}),
      );
      expect(await transcriptJobLang(storage, audio), 'pt');
    },
  );
}
