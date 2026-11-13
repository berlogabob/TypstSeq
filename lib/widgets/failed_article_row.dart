import 'package:material_ui/material_ui.dart';

import '../processing_jobs.dart';

class FailedArticleRow extends StatelessWidget {
  const FailedArticleRow({super.key, required this.jobs, required this.job});

  final ProcessingJobs jobs;
  final ProcessingJob job;

  @override
  Widget build(BuildContext context) {
    final url = job.text('url') ?? '';
    final host = Uri.tryParse(url)?.host.replaceFirst(RegExp(r'^www\.'), '');
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    return Row(
      children: [
        Expanded(
          child: Text(
            "couldn't save ${host == null || host.isEmpty ? url : host}: ${job.failureReason ?? 'unknown error'}",
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: color),
          ),
        ),
        TextButton(
          onPressed: () async {
            await jobs.retry(job);
            await jobs.refresh(jobs.storage);
          },
          style: TextButton.styleFrom(foregroundColor: color),
          child: const Text('Retry'),
        ),
      ],
    );
  }
}
