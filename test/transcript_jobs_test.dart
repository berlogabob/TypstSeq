import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tylog_core/tylog_core.dart';
import 'package:tylog/audio/transcript_jobs.dart';

void main() {
  late Directory dir;
  late LocalVaultStorage storage;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('tylog_transcript_jobs_');
    storage = LocalVaultStorage(dir);
    addTearDown(() => dir.delete(recursive: true));
  });

  test(
    'enqueueTranscript writes a queued JSON job and transcriptJobStatus reads it',
    () async {
      const audio = '/assets/clips/voice.mp3';
      const note = '/notes/voice.typ';

      await enqueueTranscript(storage, audioPath: audio, notePath: note);

      final path = transcriptJobPath(audio);
      expect(path, endsWith('.json'));
      expect(await storage.exists(path), isTrue);

      final data = jsonDecode(await storage.readText(path)) as Map<String, dynamic>;
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
        jsonEncode({
          'audio': audio,
          'note': note,
          'status': 'processing',
        }),
      );

      await enqueueTranscript(storage, audioPath: audio, notePath: note);

      final data = jsonDecode(await storage.readText(path)) as Map<String, dynamic>;
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
      jsonEncode({
        'audio': audio,
        'note': note,
        'status': 'failed',
      }),
    );

    await enqueueTranscript(storage, audioPath: audio, notePath: note);

    final data = jsonDecode(await storage.readText(path)) as Map<String, dynamic>;
    expect(data['status'], 'queued');
    expect(await transcriptJobStatus(storage, audio), 'queued');
  });

  test(
    'transcriptJobStatus is null when no job exists and transcriptJobPath is stable',
    () async {
      expect(await transcriptJobStatus(storage, '/assets/clips/missing.mp3'), isNull);

      const audio = '/assets/clips/voice.mp3';
      expect(transcriptJobPath(audio), transcriptJobPath(audio));
      expect(transcriptJobPath(audio), endsWith('.json'));
    },
  );
}
