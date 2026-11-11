part of '../app_mobile.dart';

extension _ReadingFlow on _HomeScreenState {
  Future<void> _updateReadingPreferences(
    double fontScale,
    bool nightMode,
  ) async {
    final registry = vaultRegistry;
    if (registry == null) return;
    await registry.updateReadingPreferences(
      fontScale: fontScale,
      nightMode: nightMode,
    );
  }

  /// Mirrors this device's recents/progress into the vault at
  /// `_system/reading/<deviceId>.json` so it syncs across devices. Best
  /// effort — vaults.json stays the offline source of truth for this device.
  Future<void> _writeReadingFile() async {
    final v = vault;
    final entry = _activeRegistryEntry;
    final id = vaultRegistry?.deviceId;
    if (v == null || entry == null || id == null || id.isEmpty) return;
    try {
      await v.storage.writeText(
        '_system/reading/$id.json',
        jsonEncode({
          'schema': 1,
          'recent': [for (final r in entry.recent) r.toJson()],
        }),
      );
    } catch (_) {}
  }

  /// Cross-device recents: the synced merged view overlaid by this device's
  /// in-memory registry (registry wins ties, so the local session stays
  /// authoritative). Degrades to exactly the registry list when no reading
  /// files exist in the vault.
  List<RecentNote> _mergedRecent() {
    final byPath = {for (final r in workspace.mergedReading) r.path: r};
    for (final r in _activeRegistryEntry?.recent ?? const <RecentNote>[]) {
      final existing = byPath[r.path];
      if (existing == null || !r.openedAt.isBefore(existing.openedAt)) {
        byPath[r.path] = r;
      }
    }
    return byPath.values.toList()
      ..sort((a, b) => b.openedAt.compareTo(a.openedAt));
  }

  Future<void> _recordReadingProgress(String path, double progress) async {
    final entry = _activeRegistryEntry;
    if (entry == null) return;
    await vaultRegistry!.recordProgress(entry, path, progress);
    unawaited(_writeReadingFile());
    if (progress < 0.98) return;
    // Finishing an article marks it read; richer custom statuses
    // (e.g. "summarized") are left alone.
    final finished = index?.notesByPath[path];
    final status = finished?.properties['status'] as String?;
    if (finished != null &&
        finished.kind == 'article' &&
        (status == null || status == 'unread' || status == 'reading')) {
      await _logReading(finished.title);
      await _setReadStatus(finished, 'read');
      await _setNoteProperty(finished, 'finished', isoDay(DateTime.now()));
    }
  }

  /// Appends a reading-log line to today's daily note so "what I read"
  /// survives even after the article file itself is deleted. Plain text on
  /// purpose — a link would dangle once the article is gone.
  Future<void> _logReading(String title, {String? rating, String? url}) async {
    final v = vault;
    if (v == null || title.trim().isEmpty) return;
    try {
      final dayPath = await workspace.ensureTodayNote();
      final safeTitle = escapeMarkup(title.trim());
      final line = readingLogLine(safeTitle, rating: rating, url: url);
      // The daily note may be the currently-open (possibly dirty) document;
      // writing to disk behind the editor's back would be clobbered by the
      // next autosave, so route through the editor buffer in that case.
      final isOpen = note == dayPath;
      String apply(String current) =>
          applyReadingLog(current, safeTitle, line, rated: rating != null);
      if (isOpen) {
        final source = _currentSource();
        final updated = apply(source);
        if (updated == source) return; // already logged today
        _loadSource(updated);
        _queueAutosave();
      } else {
        // Transform the note's current text: a pre-read snapshot would drop
        // anything written to the day note in between.
        await workspace.mutateNote(dayPath, apply);
      }
    } catch (_) {
      // Logging must never break the reading/rating flow.
    }
  }

  List<(NoteRef note, double progress)> _recentNotes() {
    final notesByPath = index?.notesByPath;
    if (notesByPath == null) return const [];
    final result = <(NoteRef, double)>[];
    for (final recent in _mergedRecent()) {
      if (recent.progress >= 0.98) continue; // finished — nothing to continue
      final note = notesByPath[recent.path];
      if (note == null) continue;
      if (!continueReadingEligible(note)) continue;
      result.add((note, recent.progress));
      if (result.length == 8) break;
    }
    return result;
  }

  /// Opens [path] straight into reading mode (the shelf/rail "resume" tap).
  void _readPath(String path) {
    final fromList = mode == 'library' || mode == 'journal' || mode == 'graph';
    unawaited(
      _openNote(path).then((opened) {
        if (!mounted || !opened) return;
        if (fromList ||
            (_backViews.isNotEmpty && _backViews.last.mode == 'today')) {
          _rebuild(() => mode = 'read');
        } else {
          _enterView('read');
        }
      }),
    );
  }

  Future<void> _deleteArticle(NoteRef ref) async {
    final v = vault;
    if (v == null) return;
    final confirmed = await showConfirmDialog(
      context,
      title: ref.kind == 'screenshot' ? 'Delete screenshot?' : 'Delete article',
      message:
          '"${ref.title}" will be removed from the vault. '
          'There is no recovery.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    if (note == ref.path) {
      // Move the editor off the doomed file first, so a dirty autosave
      // can't resurrect it; then return to the library shelf.
      if (!await _openToday()) {
        if (mounted) showSnack(context, 'Could not save the open article.');
        return;
      }
      if (mounted) {
        _backViews.clear();
        _rebuild(() {
          primaryDestination = 2;
          mode = 'library';
        });
      }
    }
    try {
      if (!await workspace.deleteNote(ref.path)) {
        throw StateError('The article changed while it was being deleted');
      }
    } catch (error) {
      if (mounted) showSnack(context, 'Could not delete ${ref.title}: $error');
      return;
    }
    await workspace.refreshIndex(always: true);
    if (mounted) showSnack(context, 'Deleted ${ref.title}');
  }

  Future<void> _rateArticle(String path, String value) async {
    if (vault == null) return;
    try {
      final updated = await workspace.mutateNote(
        path,
        (source) => replaceNoteProperty(source, 'rating', value),
      );
      if (!updated) {
        if (mounted) {
          showSnack(context, 'Could not rate that article: the vault changed.');
        }
        return;
      }
    } on StateError catch (error) {
      if (mounted) {
        showSnack(context, 'Could not rate that article: ${error.message}');
      }
      return;
    } catch (error) {
      if (mounted) showSnack(context, 'Could not rate that article: $error');
      return;
    }
    final rated = index?.notesByPath[path];
    if (rated != null) {
      await _logReading(
        rated.title,
        rating: value,
        url: rated.properties['url'] as String?,
      );
    }
    if (value != 'shit' || !mounted) return;
    if (rated != null) await _deleteArticle(rated);
  }
}
