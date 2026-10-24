part of '../app_mobile.dart';

/// Pages that are never articles: sign-ins, searches, access errors, images.
/// Same rule as `_NOT_ARTICLES` in tool/enrich_worker.py.
final _notArticles = RegExp(
  r'//(?:login|accounts|auth)\.|google\.[a-z.]+/search|/_layouts/|AccessDenied'
  r'|\.(?:png|jpe?g|gif|webp|svg|zip)(?:[?#]|$)',
  caseSensitive: false,
);

/// Links typed in the journal become articles (through the existing article
/// pipeline), and each bare link then becomes a link to its article.
extension _ArticleLinksFlow on _HomeScreenState {
  /// Magic > Save links as articles: the bare links in the selection (in the
  /// whole note when nothing is selected) are queued for the article worker;
  /// links whose article is already done are replaced at once.
  Future<void> _saveLinksAsArticles() async {
    final v = vault;
    final path = note;
    if (v == null || path == null) return;
    if (dirty && !await _save(syncAfter: false)) return;
    final selected = richController.selectedPlainText;
    final urls = {
      for (final link in bareLinks(workspace.source))
        if (selected.isEmpty || selected.contains(link.url)) link.url,
    };
    final relinked = await _relinkArticles(v, only: path);
    var queued = 0;
    for (final url in urls) {
      if (_notArticles.hasMatch(url)) continue;
      final job = SharedArticle(url, origin: path);
      if (await v.storage.exists(job.path)) continue;
      await job.enqueue(v.storage);
      queued++;
    }
    if (!mounted) return;
    showSnack(
      context,
      queued == 0 && relinked == 0
          ? 'No new links to save'
          : [
              if (queued > 0)
                '$queued ${queued == 1 ? 'link' : 'links'} queued as articles',
              if (relinked > 0) 'links to ready articles updated',
            ].join('; '),
    );
  }

  /// Replaces the bare link of every finished article job in the note it came
  /// from. On its own (desktop) only past days: today may be open on another
  /// device. [only] is a user action on that note, today included.
  // ponytail: reads every job file; index jobs by origin if the folder grows
  // past a few thousand.
  Future<int> _relinkArticles(Vault v, {String? only}) async {
    final currentIndex = index;
    const directory = '_system/jobs/articles';
    if (currentIndex == null || !await v.storage.exists(directory)) return 0;
    final today = await v.todayNote();
    final byOrigin = <String, List<(String, NoteRef)>>{};
    for (final entry in await v.storage.list(path: directory)) {
      if (entry.isDirectory || !entry.path.endsWith('.json')) continue;
      try {
        if (jsonDecode(await v.storage.readText(entry.path)) case {
          'status': 'done',
          'url': final String url,
          'origin': final String origin,
          'note_path': final String notePath,
        } when only == null ? origin != today : origin == only) {
          if (currentIndex.notesByPath[notePath] case final article?) {
            byOrigin.putIfAbsent(origin, () => []).add((url, article));
          }
        }
      } catch (_) {
        // A worker may be rewriting the file; next pass.
      }
    }
    var changed = 0;
    for (final MapEntry(key: origin, value: done) in byOrigin.entries) {
      final String source;
      try {
        source = origin == note
            ? workspace.source
            : await v.storage.readText(origin);
      } catch (_) {
        continue;
      }
      var linked = source;
      for (final (url, article) in done) {
        linked = linkArticle(linked, url, article);
      }
      if (linked == source) continue;
      if (await workspace.mutateNote(
        origin,
        (current) => current == source ? linked : current,
      )) {
        changed++;
      }
    }
    return changed;
  }

  /// Desktop: at most every 5 minutes, whenever the workspace changes.
  void _queueArticleRelink() {
    final v = vault;
    if (v == null || !_enrichAutoWrite) return;
    final now = DateTime.now();
    if (_articleRelinkAt case final last?
        when now.difference(last) < const Duration(minutes: 5)) {
      return;
    }
    _articleRelinkAt = now;
    unawaited(_relinkArticles(v).catchError((_) => 0));
  }
}
