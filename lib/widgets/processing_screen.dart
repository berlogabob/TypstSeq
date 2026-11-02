import 'package:flutter/material.dart';

import '../processing_jobs.dart';
import 'constants.dart';
import 'date_format.dart';
import 'snack.dart';

void showProcessingQueued(BuildContext context, VoidCallback? onOpen) =>
    showSnack(
      context,
      'Queued — see Processing',
      action: onOpen == null
          ? null
          : SnackBarAction(label: 'Processing', onPressed: onOpen),
    );

class ProcessingBadge extends StatelessWidget {
  const ProcessingBadge({super.key, required this.jobs, required this.onOpen});

  final ProcessingJobs jobs;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: jobs,
    builder: (context, _) => jobs.activeCount == 0
        ? const SizedBox.shrink()
        : Tooltip(
            message: 'Processing · ${jobs.activeCount}',
            child: ActionChip(
              avatar: const Icon(Icons.hourglass_top, size: kIconSmall),
              label: Text('${jobs.activeCount}'),
              onPressed: onOpen,
            ),
          ),
  );
}

class ProcessingScreen extends StatefulWidget {
  const ProcessingScreen({
    super.key,
    required this.jobs,
    required this.onQueued,
    required this.titleForPath,
  });

  final ProcessingJobs jobs;
  final ValueChanged<String> onQueued;
  final String? Function(String path) titleForPath;

  @override
  State<ProcessingScreen> createState() => _ProcessingScreenState();
}

const _oldAge = Duration(days: 3);

class _ProcessingScreenState extends State<ProcessingScreen> {
  final _retrying = <String>{};
  bool _olderOpen = false;

  Future<void> _retry(ProcessingJob job) async {
    setState(() => _retrying.add(job.path));
    try {
      final queued = await widget.jobs.retry(job);
      if (queued) widget.onQueued(job.path);
      await widget.jobs.refresh(widget.jobs.storage);
      if (mounted && queued) {
        showProcessingQueued(context, () {
          widget.jobs.refresh(widget.jobs.storage);
        });
      }
    } catch (error) {
      if (mounted) showSnack(context, 'Could not retry: $error');
    } finally {
      if (mounted) setState(() => _retrying.remove(job.path));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Processing'),
      actions: [
        IconButton(
          tooltip: 'Refresh processing',
          icon: const Icon(Icons.refresh),
          onPressed: () => widget.jobs.refresh(widget.jobs.storage),
        ),
      ],
    ),
    body: SafeArea(
      child: ListenableBuilder(
        listenable: widget.jobs,
        builder: (context, _) {
          final jobs = widget.jobs;
          if (jobs.loading && jobs.jobs.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }
          if (jobs.error != null) {
            return Center(child: Text('Could not read jobs: ${jobs.error}'));
          }
          if (jobs.jobs.isEmpty) {
            return const Center(child: Text('No processing jobs'));
          }
          final cutoff = DateTime.now().subtract(_oldAge);
          final recent = <ProcessingJob>[];
          final older = <ProcessingJob>[];
          for (final job in jobs.jobs) {
            final at = job.activityAt;
            final finished = job.status == 'done' || job.status == 'failed';
            (finished && at != null && at.isBefore(cutoff) ? older : recent)
                .add(job);
          }
          return RefreshIndicator(
            onRefresh: () => jobs.refresh(jobs.storage),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(kSpace12),
              children: [
                for (final job in recent) _job(job),
                if (older.isNotEmpty)
                  Card(
                    child: ListTile(
                      key: const ValueKey('older-jobs'),
                      title: Text('Older (${older.length})'),
                      trailing: Icon(
                        _olderOpen ? Icons.expand_less : Icons.expand_more,
                      ),
                      onTap: () => setState(() => _olderOpen = !_olderOpen),
                    ),
                  ),
                if (_olderOpen)
                  for (final job in older) _job(job),
              ],
            ),
          );
        },
      ),
    ),
  );

  Widget _job(ProcessingJob job) {
    final scheme = Theme.of(context).colorScheme;
    final kind = switch (job.kind) {
      'articles' => 'Article',
      'transcripts' => 'Transcription',
      'translations' => 'Translation',
      _ => job.kind,
    };
    final status = switch (job.status) {
      'queued' => 'Queued',
      'processing' => 'Processing',
      'done' => 'Done',
      _ => 'Failed',
    };
    final notePath = job.notePath;
    final title =
        job.text('title') ??
        (notePath == null ? null : widget.titleForPath(notePath)) ??
        job.title;
    return Card(
      key: ValueKey(job.path),
      child: Padding(
        padding: const EdgeInsets.all(kSpace16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: kSpace4),
            Text(
              [
                kind,
                if (job.text('target') case final target?) target.toUpperCase(),
                status,
              ].join(' · '),
            ),
            if (notePath != null && notePath != title) Text(notePath),
            if (job.text('url') case final url? when url != title) Text(url),
            for (final (key, label) in const [
              ('shared_at', 'Added'),
              ('requested_at', 'Requested'),
              ('processing_at', 'Started'),
              ('started_at', 'Started'),
              ('finished_at', 'Finished'),
            ])
              if (job.text(key) case final time?)
                Text('$label: ${shortStamp(time)}'),
            if (job.text('error') case final error?)
              Text(error, style: TextStyle(color: scheme.error)),
            if (job.status == 'failed')
              TextButton.icon(
                onPressed: _retrying.contains(job.path)
                    ? null
                    : () => _retry(job),
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
          ],
        ),
      ),
    );
  }
}
