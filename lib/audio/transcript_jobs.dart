import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:tylog_core/storage.dart';

/// Queue for a local transcription worker. Same shape as article jobs
/// (`lib/article_jobs.dart`): one JSON file per audio file under the synced
/// `_system/` prefix, so a worker on another machine can claim it. Contract:
/// docs/audio-transcription.md.
String transcriptJobPath(String audioPath) =>
    '_system/jobs/transcripts/${sha1.convert(utf8.encode(audioPath))}.json';

Future<String?> transcriptJobStatus(
  VaultStorage storage,
  String audioPath,
) async {
  final path = transcriptJobPath(audioPath);
  if (!await storage.exists(path)) return null;
  try {
    final data = jsonDecode(await storage.readText(path));
    return data is Map ? data['status'] as String? : null;
  } catch (_) {
    return null;
  }
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
