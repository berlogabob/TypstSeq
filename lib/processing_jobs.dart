import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:tylog_core/storage.dart';

class ProcessingJob {
  const ProcessingJob(this.path, this.kind, this.data);

  final String path;
  final String kind;
  final Map<String, dynamic> data;

  String get status => data['status'] as String;
  bool get active => status == 'queued' || status == 'processing';
  String? text(String key) => data[key] is String ? data[key] as String : null;
  String? get notePath => text('note_path') ?? text('note') ?? text('origin');
  String get title =>
      text('title') ?? notePath ?? text('url') ?? text('audio') ?? path;
  DateTime? get requestedAt =>
      DateTime.tryParse(text('requested_at') ?? text('shared_at') ?? '');
  DateTime? get activityAt =>
      DateTime.tryParse(text('finished_at') ?? text('processing_at') ?? '') ??
      requestedAt;
}

/// Discover kinds instead of hard-coding pipelines, using SAF-safe storage calls.
Future<List<ProcessingJob>> loadProcessingJobs(VaultStorage storage) async {
  const root = '_system/jobs';
  if (!await storage.exists(root)) return const [];
  final jobs = <ProcessingJob>[];
  for (final directory in await storage.list(path: root)) {
    if (!directory.isDirectory) continue;
    final kind = directory.path.split('/').last;
    for (final entry in await storage.list(path: directory.path)) {
      if (entry.isDirectory || !entry.path.endsWith('.json')) continue;
      try {
        final data = jsonDecode(await storage.readText(entry.path));
        if (data is! Map<String, dynamic> ||
            !const [
              'queued',
              'processing',
              'done',
              'failed',
            ].contains(data['status'])) {
          continue;
        }
        jobs.add(ProcessingJob(entry.path, kind, data));
      } on FormatException {
        // A worker may be replacing this file; the next revision retries it.
      }
    }
  }
  int rank(ProcessingJob job) => switch (job.status) {
    'processing' => 0,
    'queued' => 1,
    _ => 2,
  };
  jobs.sort((a, b) {
    final status = rank(a).compareTo(rank(b));
    if (status != 0) return status;
    final time = (b.activityAt ?? DateTime(0)).compareTo(
      a.activityAt ?? DateTime(0),
    );
    return time == 0 ? a.path.compareTo(b.path) : time;
  });
  return jobs;
}

/// Shared snapshot for the shell badge and Processing, refreshed on sync/index
/// revisions and local queue writes rather than on editor keystrokes.
class ProcessingJobs extends ChangeNotifier {
  VaultStorage? storage;
  List<ProcessingJob> jobs = const [];
  Object? error;
  bool loading = false;
  int _generation = 0;
  bool _disposed = false;

  int get activeCount => jobs.where((job) => job.active).length;

  Future<void> refresh(VaultStorage? nextStorage) async {
    if (_disposed) return;
    final generation = ++_generation;
    if (!identical(storage, nextStorage)) jobs = const [];
    storage = nextStorage;
    loading = nextStorage != null;
    error = null;
    notifyListeners();
    try {
      final next = nextStorage == null
          ? <ProcessingJob>[]
          : await loadProcessingJobs(nextStorage);
      if (_disposed || generation != _generation) return;
      jobs = next;
    } catch (failure) {
      if (_disposed || generation != _generation) return;
      error = failure;
    }
    if (_disposed || generation != _generation) return;
    loading = false;
    notifyListeners();
  }

  Future<bool> retry(ProcessingJob job, {DateTime? now}) async {
    final current = storage;
    if (current == null || !jobs.contains(job)) return false;
    // Re-read: sync may already have replaced the failed snapshot with a claim.
    final data = jsonDecode(await current.readText(job.path));
    if (!identical(current, storage) ||
        data is! Map<String, dynamic> ||
        data['status'] != 'failed') {
      return false;
    }
    data['status'] = 'queued';
    data[job.kind == 'articles' ? 'shared_at' : 'requested_at'] =
        (now ?? DateTime.now()).toUtc().toIso8601String();
    for (final key in ['error', 'finished_at', 'processing_at', 'started_at']) {
      data.remove(key);
    }
    await current.writeText(job.path, jsonEncode(data));
    return true;
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
