part of '../app_mobile.dart';

extension _KnowledgeFlow on _HomeScreenState {
  Future<void> _showKnowledge({
    KnowledgeView initialView = KnowledgeView.search,
    String? initialQuery,
  }) async {
    if (!mounted) return;
    final v = vault;
    if (v == null) return;
    _loadOltForToday();
    final generation = ++_destinationGeneration;
    ++_openGeneration;
    final previousDestination = primaryDestination;
    _rebuild(() => primaryDestination = 3);
    final searchStore = SavedSearchStore(v.storage);
    var savedSearches = <SavedSearch>[];
    final ready = ValueNotifier<bool>(false);
    final navigator = Navigator.of(context);
    late final MaterialPageRoute<void> route;
    route = MaterialPageRoute<void>(
      builder: (_) => ValueListenableBuilder<bool>(
        valueListenable: ready,
        builder: (_, loaded, _) => loaded
            ? ListenableBuilder(
                listenable: workspace,
                builder: (_, _) {
                  final ix =
                      index ??
                      VaultIndex(notesByPath: {}, backlinksByTarget: {});
                  Future<void> openFromSearch(
                    String path,
                    String? query,
                  ) async {
                    final selection = ++_destinationGeneration;
                    final searchDestination = primaryDestination;
                    _rebuild(() => primaryDestination = previousDestination);
                    await workspace.materializeEvent(path);
                    // Search stays open until the note is actually shown.
                    final opened =
                        mounted &&
                        selection == _destinationGeneration &&
                        await _openNote(
                          path,
                          rememberView: false,
                          searchQuery: query,
                        );
                    if (!mounted) return;
                    if (!opened) {
                      if (selection == _destinationGeneration) {
                        _rebuild(() => primaryDestination = searchDestination);
                        showSnack(
                          context,
                          "Couldn't open ${ix.notesByPath[path]?.title ?? path}: the note could not be loaded",
                        );
                      }
                      return;
                    }
                    // An audio note pushes its own route above Search.
                    if (route.isActive) navigator.removeRoute(route);
                    // Search is a route; recreate it when leaving its editor.
                    _rememberView(knowledge: initialView, searchQuery: query);
                    _rebuild(() {});
                  }

                  return KnowledgeScreen(
                    shelfPrefs: vaultRegistry?.shelfPrefs ?? const {},
                    onShelfPrefsChanged: (prefs) {
                      final registry = vaultRegistry;
                      if (registry != null) {
                        unawaited(
                          registry.updateShelfPrefs({
                            ...registry.shelfPrefs,
                            ...prefs,
                          }),
                        );
                      }
                    },
                    onSetTaskStatus: _setTaskStatus,
                    onSetTaskField: _setTaskField,
                    initialView: initialView,
                    initialQuery: initialQuery ?? '',
                    index: ix,
                    search: (query, tag, status) =>
                        _searchNotes(ix, query, tag: tag, status: status),
                    searchState: workspace,
                    // The worker loads its search index on the first query,
                    // so the screen only waits for the note index itself.
                    searchReady: () =>
                        workspace.searchReady || workspace.index != null,
                    searchRevision: () => workspace.searchRevision,
                    // Checked per query: the controller may finish installing or
                    // indexing while the search screen is open.
                    vectorSearch: (query) async =>
                        await _semantic?.searchNotes(query) ?? const [],
                    citedSearch: (query) async =>
                        await _semantic?.citations(query) ?? const [],
                    resolveMissing: (id) {
                      final note = ix.notesByPath[id];
                      if (note == null) return null;
                      return PkmsSearchResult(
                        id: note.path,
                        path: note.path,
                        title: note.title,
                        kind: note.kind,
                        tags: note.tags,
                        score: 0,
                      );
                    },
                    savedSearches: savedSearches,
                    onSaveSearch: (search) async {
                      final next = [
                        ...savedSearches.where((s) => s.name != search.name),
                        search,
                      ];
                      await searchStore.save(next);
                      savedSearches = next;
                      _queueCloudSync();
                    },
                    onDeleteSearch: (search) async {
                      final next = savedSearches
                          .where((s) => s.name != search.name)
                          .toList();
                      await searchStore.save(next);
                      savedSearches = next;
                      _queueCloudSync();
                    },
                    problems: _knowledgeProblems(),
                    // Same close-and-open as a search hit, minus the reveal.
                    onOpenNote: (path) => unawaited(openFromSearch(path, null)),
                    onCaptureTimestamp: () {
                      Navigator.of(context).pop();
                      unawaited(_captureTimestamp());
                    },
                    onOpenSearchNote: (path, query) =>
                        openFromSearch(path, query),
                    onOpenSearchCitation: (citation, query) async {
                      if (citation.sourceKind == 'note') {
                        final path = await _resolveCitationPath(citation, ix);
                        if (path == null) {
                          if (mounted) {
                            showSnack(
                              context,
                              'Could not open ${citation.sourceTitle ?? citation.sourceLocator}',
                            );
                          }
                          return;
                        }
                        await _openSearchNote(
                          path,
                          previousDestination,
                          query: query,
                          offset: citation.startOffset,
                        );
                        return;
                      }
                      await _openCitation(citation);
                    },
                    onFixProblems: _fixProblems,
                  );
                },
              )
            : Scaffold(
                appBar: AppBar(title: const Text('Search')),
                body: const Center(child: CircularProgressIndicator()),
              ),
      ),
    );
    final closed = navigator.push<void>(route);
    bool current() =>
        mounted && generation == _destinationGeneration && vault == v;
    Future<void> prepare() async {
      if (dirty && !await _save()) {
        if (current() && route.isActive) navigator.removeRoute(route);
        return;
      }
      if (!current()) return;
      unawaited(_ensureSemanticController());
      final loaded = await searchStore.load();
      if (!current()) return;
      savedSearches = loaded;
      ready.value = true;
      unawaited(workspace.refreshIndex());
    }

    unawaited(prepare());
    await closed;
    // Ignore late storage completions once this route has closed.
    if (current()) {
      ++_destinationGeneration;
      if (initialView == KnowledgeView.search) {
        await _showToday();
      } else {
        _rebuild(() => primaryDestination = previousDestination);
      }
    }
    // The outgoing route still listens during its reverse transition.
    route.completed.then((_) => ready.dispose());
  }

  /// The Problems-screen view: everything except sync conflicts (which route to
  /// their own resolver).
  List<PkmsProblem> _knowledgeProblems() =>
      (validation?.problems ?? index?.problems ?? const <PkmsProblem>[])
          .where((problem) => !problem.code.startsWith('sync-'))
          .toList();

  /// Resolves a tile's (or a whole group's) problems from the Problems screen.
  /// Returns the refreshed problem list when the vault changed, or null when
  /// the fix only navigates (opening duplicate owners to merge by hand).
  Future<List<PkmsProblem>?> _fixProblems(List<PkmsProblem> toFix) async {
    if (toFix.isEmpty) return null;
    switch (toFix.first.code) {
      case 'metadata-fallback':
        return _convertToManagedHeader(toFix);
      case 'metadata-query-failed':
        return _repairArticles(toFix);
      case 'duplicate-note-id':
      case 'duplicate-alias':
        await _openDuplicateOwners(toFix);
        return null;
      case 'broken-link':
        return _triageMissingPages(toFix);
      default:
        return null;
    }
  }

  /// Materialises the pages behind Logseq wikilinks that never had a file.
  /// Logseq treats `[[Tutorial]]` as a page regardless; the importer only
  /// reported them, so a migrated vault is left with thousands of broken links
  /// — and the persons and places the user expected are among them.
  Future<List<PkmsProblem>?> _triageMissingPages(
    List<PkmsProblem> problems,
  ) async {
    final v = vault;
    final ix = index;
    if (v == null || ix == null) return null;
    final targets = unresolvedLinkTargets(problems, {
      for (final note in ix.notes) ...note.tags,
    });
    if (targets.isEmpty) {
      showSnack(context, 'Every unresolved link is already a tag');
      return null;
    }
    final picked = await Navigator.of(context).push<Map<String, String>>(
      MaterialPageRoute(
        builder: (_) => TriageMissingPagesScreen(targets: targets),
      ),
    );
    if (picked == null || picked.isEmpty || !mounted) return null;
    if (picked.length > 100) {
      final go = await showConfirmDialog(
        context,
        title: 'Create ${picked.length} pages?',
        message: 'This writes ${picked.length} new notes, then reindexes once.',
        confirmLabel: 'Create',
      );
      if (!go || !mounted) return null;
    }
    // One id namespace for the whole batch: nextNoteId otherwise dedups against
    // the last written index, which cannot know about the note created a
    // millisecond ago — and a Cyrillic title slugs to nothing, so a run of them
    // would all collapse onto the same timestamp id.
    final ids = {for (final note in ix.notes) note.id};
    for (final entry in picked.entries) {
      await workspace.createPage(entry.key, kind: entry.value, knownIds: ids);
    }
    await workspace.refreshIndex(always: true);
    if (!mounted) return null;
    showSnack(context, 'Created ${picked.length} pages');
    return _knowledgeProblems();
  }

  /// Counts how many of [attempted] still carry [code] after a rescan — the
  /// fix snackbars report resolved-vs-still-failing, not bytes written.
  int _stillFlagged(Iterable<PkmsProblem> attempted, String code) {
    final subjects = attempted.map((p) => p.subject).toSet();
    return _knowledgeProblems()
        .where((p) => p.code == code && subjects.contains(p.subject))
        .length;
  }

  /// Repairs markdown-import artifacts that break a note's Typst metadata query
  /// ("formatting couldn't be read") so it re-parses as verified metadata.
  Future<List<PkmsProblem>?> _repairArticles(List<PkmsProblem> problems) async {
    final v = vault;
    if (v == null) return null;
    for (final problem in problems) {
      if (!await workspace.mutateNote(problem.subject, repairArticleTypst)) {
        if (mounted) {
          showSnack(context, 'Repair stopped because the vault changed.');
        }
        return null;
      }
    }
    await workspace.waitForMutationRefresh();
    if (!mounted) return null;
    final remaining = _stillFlagged(problems, 'metadata-query-failed');
    final resolved = problems.length - remaining;
    showSnack(
      context,
      remaining == 0
          ? 'Repaired ${problems.length} note${problems.length == 1 ? '' : 's'}'
          : resolved == 0
          ? "Couldn't repair $remaining note${remaining == 1 ? '' : 's'} — "
                'see Technical details for each error'
          : 'Repaired $resolved, $remaining still failing — '
                'see Technical details',
    );
    return _knowledgeProblems();
  }

  /// Upgrades legacy/fallback-parsed notes to a managed `tylog.note.with(...)`
  /// header, rebuilt from the already-parsed metadata (body untouched).
  Future<List<PkmsProblem>?> _convertToManagedHeader(
    List<PkmsProblem> problems,
  ) async {
    final v = vault;
    final ix = index;
    if (v == null || ix == null) return null;
    var converted = 0;
    var alreadyManaged = 0;
    for (final problem in problems) {
      final note = ix.notesByPath[problem.subject];
      if (note == null) continue;
      var changed = false;
      if (!await workspace.mutateNote(problem.subject, (source) {
        if (source.contains('tylog.note.with(')) {
          // The header is fine — the note is flagged because Typst couldn't
          // verify it (engine timeout/death). Rewriting the header from
          // fallback-parsed metadata fixes nothing and risks baking
          // body-recovered tags into it.
          return source;
        }
        final updated = replaceNoteHeader(
          source,
          NoteMetadataDraft.fromNote(note),
        );
        changed = updated != source;
        return updated;
      })) {
        if (mounted) {
          showSnack(context, 'Conversion stopped because the vault changed.');
        }
        return null;
      }
      if (changed) converted++;
      if (!changed) alreadyManaged++;
    }
    await workspace.waitForMutationRefresh();
    if (!mounted) return null;
    final remaining = _stillFlagged(problems, 'metadata-fallback');
    final parts = [
      if (converted > 0)
        'Converted $converted note${converted == 1 ? '' : 's'}',
      if (alreadyManaged > 0)
        '$alreadyManaged already managed — Typst couldn\'t verify '
            'th${alreadyManaged == 1 ? 'at note' : 'ose notes'}',
    ];
    showSnack(
      context,
      parts.isEmpty
          ? 'Nothing to convert'
          : '${parts.join('; ')}'
                '${remaining > 0 ? ' ($remaining still unverified)' : ''}',
    );
    return _knowledgeProblems();
  }

  /// A duplicated id/date can only be resolved by a human merge, so list every
  /// file that claims it and open the tapped one. Accepts a whole group so the
  /// list's "Open files" action shows all duplicates, not just the first.
  Future<void> _openDuplicateOwners(List<PkmsProblem> problems) async {
    List<String> owners(PkmsProblem problem) =>
        problem.targets.isNotEmpty ? problem.targets : [problem.subject];
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: false,
      builder: (context) => AppSheet(
        title: 'Duplicate owners',
        children: [
          const ListTile(
            subtitle: Text('Open each to compare, then merge or delete one.'),
          ),
          for (final problem in problems) ...[
            ListTile(
              title: Text(
                '“${problem.subject}” is claimed by ${owners(problem).length} files',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            for (final path in owners(problem))
              ListTile(
                leading: const Icon(Icons.description_outlined),
                title: Text(path),
                onTap: () => Navigator.pop(context, path),
              ),
          ],
        ],
      ),
    );
    if (choice == null || !mounted) return;
    Navigator.pop(context); // leave the Problems screen
    await _openPath(choice);
  }
}
