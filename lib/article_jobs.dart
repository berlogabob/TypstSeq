import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:tylog_core/storage.dart';

/// A shared web URL, preserving its exact spelling for the worker's job id.
class SharedArticle {
  const SharedArticle(this.url, {this.title});

  final String url;
  final String? title;

  static SharedArticle? parse(String text, {String? title}) {
    for (final match in RegExp(r'https?://[^\s<>]+').allMatches(text)) {
      final url = match.group(0)!;
      final uri = Uri.tryParse(url);
      if (uri == null || uri.host.isEmpty) continue;
      final label = title?.trim();
      return SharedArticle(
        url,
        title: label == null || label.isEmpty ? null : label,
      );
    }
    return null;
  }

  String get path =>
      '_system/jobs/articles/${sha1.convert(utf8.encode(url))}.json';

  /// Re-sharing must not reset a claimed or completed job.
  Future<void> enqueue(VaultStorage storage, {DateTime? now}) async {
    if (await storage.exists(path)) return;
    await storage.createDirectory('_system/jobs/articles');
    await storage.writeText(
      path,
      jsonEncode({
        'url': url,
        if (title != null) 'title': title,
        'shared_at': (now ?? DateTime.now()).toUtc().toIso8601String(),
        'status': 'queued',
      }),
    );
  }
}

class ArticleJob {
  const ArticleJob({
    required this.path,
    required this.url,
    required this.status,
    this.title,
  });

  final String path;
  final String url;
  final String status;
  final String? title;
}

Future<List<ArticleJob>> loadArticleJobs(VaultStorage storage) async {
  const directory = '_system/jobs/articles';
  if (!await storage.exists(directory)) return const [];
  final jobs = <ArticleJob>[];
  for (final entry in await storage.list(path: directory)) {
    if (entry.isDirectory || !entry.path.endsWith('.json')) continue;
    try {
      final data = jsonDecode(await storage.readText(entry.path));
      if (data is! Map<String, dynamic>) continue;
      final status = data['status'];
      final url = data['url'];
      if ((status != 'queued' && status != 'processing') ||
          url is! String ||
          SharedArticle.parse(url)?.url != url) {
        continue;
      }
      jobs.add(
        ArticleJob(
          path: entry.path,
          url: url,
          status: status as String,
          title: data['title'] is String ? data['title'] as String : null,
        ),
      );
    } on FormatException {
      // A worker can be partway through replacing a status file. Retry on refresh.
    }
  }
  jobs.sort((a, b) => a.path.compareTo(b.path));
  return jobs;
}
