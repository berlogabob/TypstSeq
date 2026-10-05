import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/article_jobs.dart';
import 'package:tylog/vault_storage.dart';

void main() {
  late Directory root;
  late LocalVaultStorage storage;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('tylog_article_jobs_');
    storage = LocalVaultStorage(root);
  });
  tearDown(() => root.delete(recursive: true));

  test('extracts a web URL and optional title, rejects non-web shares', () {
    final shared = SharedArticle.parse(
      'Read this\nhttps://example.org/a?q=1#b',
      title: ' A title ',
    );
    expect(shared!.url, 'https://example.org/a?q=1#b');
    expect(shared.title, 'A title');
    expect(SharedArticle.parse('plain text'), isNull);
    expect(SharedArticle.parse('file:///tmp/a'), isNull);
    expect(SharedArticle.parse('https:///'), isNull);
  });

  test(
    'writes SHA1 job contract and preserves a worker claim on re-share',
    () async {
      const url = 'https://example.org/a';
      final shared = SharedArticle.parse(url, title: 'Article')!;
      expect(
        shared.path,
        '_system/jobs/articles/${sha1.convert(utf8.encode(url))}.json',
      );
      await shared.enqueue(storage, now: DateTime.utc(2026, 10, 5, 12, 34));
      expect(jsonDecode(await storage.readText(shared.path)), {
        'url': url,
        'title': 'Article',
        'shared_at': '2026-10-05T12:34:00.000Z',
        'status': 'queued',
      });
      final processing = jsonEncode({'url': url, 'status': 'processing'});
      await storage.writeText(shared.path, processing);
      await shared.enqueue(storage);
      expect(await storage.readText(shared.path), processing);
    },
  );

  test(
    'loads only pending jobs, tolerates incomplete or invalid JSON',
    () async {
      for (final status in ['queued', 'processing', 'done', 'error']) {
        await storage.writeText(
          '_system/jobs/articles/$status.json',
          jsonEncode({'url': 'https://example.org/$status', 'status': status}),
        );
      }
      await storage.writeText('_system/jobs/articles/broken.json', '{');
      await storage.writeText(
        '_system/jobs/articles/bad.json',
        '{"status":"queued","url":42}',
      );
      expect((await loadArticleJobs(storage)).map((job) => job.status), [
        'processing',
        'queued',
      ]);
      await storage.writeText(
        '_system/jobs/articles/queued.json',
        '{"url":"https://example.org/queued","status":"done"}',
      );
      expect((await loadArticleJobs(storage)).map((job) => job.status), [
        'processing',
      ]);
    },
  );
}
