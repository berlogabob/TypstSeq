import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:tylog_core/storage.dart';

/// Queue for a local transcription worker. Same shape as article jobs
/// (`lib/article_jobs.dart`): one JSON file per audio file under the synced
/// `_system/` prefix, so a worker on another machine can claim it. Contract:
/// docs/audio-transcription.md.
String transcriptJobPath(String audioPath) =>
    '_system/jobs/transcripts/${sha1.convert(utf8.encode(audioPath))}.json';

Future<Map<String, Object?>?> _readJob(
  VaultStorage storage,
  String path,
) async {
  if (!await storage.exists(path)) return null;
  try {
    final data = jsonDecode(await storage.readText(path));
    return data is Map ? data.cast<String, Object?>() : null;
  } catch (_) {
    return null;
  }
}

Future<String?> transcriptJobStatus(
  VaultStorage storage,
  String audioPath,
) async =>
    (await _readJob(storage, transcriptJobPath(audioPath)))?['status']
        as String?;

/// ISO code the worker detected when it transcribed [audioPath], if any.
Future<String?> transcriptJobLang(
  VaultStorage storage,
  String audioPath,
) async =>
    (await _readJob(storage, transcriptJobPath(audioPath)))?['lang'] as String?;

/// One job per (audio, target language); see docs/audio-transcription.md.
String translationJobPath(String audioPath, String target) =>
    '_system/jobs/translations/${sha1.convert(utf8.encode('$audioPath\n$target'))}.json';

Future<String?> translationJobStatus(
  VaultStorage storage,
  String audioPath,
  String target,
) async =>
    (await _readJob(storage, translationJobPath(audioPath, target)))?['status']
        as String?;

/// Same re-request rule as [enqueueTranscript]: only a failed job re-queues.
Future<void> enqueueTranslation(
  VaultStorage storage, {
  required String audioPath,
  required String notePath,
  required String target,
  required String sourceLang,
  DateTime? now,
}) async {
  final status = await translationJobStatus(storage, audioPath, target);
  if (status != null && status != 'failed') return;
  await storage.createDirectory('_system/jobs/translations');
  await storage.writeText(
    translationJobPath(audioPath, target),
    jsonEncode({
      'audio': audioPath,
      'note': notePath,
      'target': target,
      'source_lang': sourceLang,
      'requested_at': (now ?? DateTime.now()).toUtc().toIso8601String(),
      'status': 'queued',
    }),
  );
}

/// Re-requesting never resets a claimed or finished job; only a failed one is
/// queued again.
Future<void> enqueueTranscript(
  VaultStorage storage, {
  required String audioPath,
  required String notePath,
  DateTime? now,
}) async {
  final status = await transcriptJobStatus(storage, audioPath);
  if (status != null && status != 'failed') return;
  await storage.createDirectory('_system/jobs/transcripts');
  await storage.writeText(
    transcriptJobPath(audioPath),
    jsonEncode({
      'audio': audioPath,
      'note': notePath,
      'requested_at': (now ?? DateTime.now()).toUtc().toIso8601String(),
      'status': 'queued',
    }),
  );
}
