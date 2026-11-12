part of '../app_mobile.dart';

/// What the Mentions strip shows for one day.
typedef _EnrichView = ({
  List<EnrichDecision> decisions,
  List<String> tags,
  List<EnrichMarkerOffer> markers,
  List<EnrichLoanOffer> loans,
  String source,
});

const _EnrichView _noEnrich = (
  decisions: [],
  tags: [],
  markers: [],
  loans: [],
  source: '',
);

EnrichMemory _buildEnrichMemory((VaultIndex, List<EnrichFeedback>) input) =>
    EnrichMemory.build(input.$1, input.$2);

EnrichDayResolution _resolveEnrichDay(
  (EnrichMentions, NoteRef, EnrichMemory, VaultIndex, String) input,
) => resolveEnrichDay(input.$1, input.$2, input.$3, input.$4, input.$5);

typedef _EnrichPageWork = ({
  String path,
  NoteRef ref,
  String source,
  EnrichMentions mentions,
});

List<EnrichDayResolution> _resolveEnrichPage(
  (List<_EnrichPageWork>, EnrichMemory, VaultIndex) input,
) => [
  for (final work in input.$1)
    resolveEnrichDay(work.mentions, work.ref, input.$2, input.$3, work.source),
];

/// Day-log enrichment in the app: reads the worker's mentions files,
/// resolves them with [EnrichMemory], and records decisions in the ledger.
extension _EnrichFlow on _HomeScreenState {
  bool get _enrichAutoWrite =>
      defaultTargetPlatform != TargetPlatform.android &&
      defaultTargetPlatform != TargetPlatform.iOS;

  /// Called on every workspace change; does work only when the open note or
  /// the index changed.
  void _queueEnrichRefresh() {
    final key = (vault, note, workspace.indexRevision);
    if (_enrichRevision == key) return;
    final previous = _enrichRevision;
    _enrichRevision = key;
    if (_enrichAutoWrite) {
      if (previous case (final Vault oldVault, final String? oldPath, _)
          when identical(oldVault, vault) &&
              oldPath != null &&
              oldPath.startsWith('daily/') &&
              oldPath != note) {
        unawaited(
          _applyClosedDayEnrichment(oldVault, oldPath, key).catchError((
            Object error,
            StackTrace stack,
          ) {
            _enrichTrace('$oldPath auto-write error $error');
          }),
        );
      }
    }
    unawaited(_refreshEnrichment());
  }

  Future<void> _applyClosedDayEnrichment(
    Vault v,
    String path,
    (Vault?, String?, int) navigation,
  ) async {
    final currentIndex = index;
    if (currentIndex == null ||
        !identical(vault, v) ||
        note == path ||
        _enrichRevision != navigation) {
      return;
    }
    final ref = currentIndex.notesByPath[path];
    if (ref == null) return;
    final mentions = await _readMentions(v, path);
    if (mentions == null ||
        !identical(vault, v) ||
        note == path ||
        _enrichRevision != navigation ||
        workspace.indexRevision != navigation.$3) {
      return;
    }
    final source = await v.storage.readText(path);
    if (enrichContentSha(source) != mentions.contentSha) return;
    final memory = await _enrichMemory(v, currentIndex);
    if (!identical(vault, v) ||
        note == path ||
        _enrichRevision != navigation ||
        workspace.indexRevision != navigation.$3) {
      return;
    }
    final resolution = await compute(_resolveEnrichDay, (
      mentions,
      ref,
      memory,
      currentIndex,
      source,
    ));
    final links = resolution.decisions
        .where((decision) => decision.status == EnrichStatus.linked)
        .toList();
    final tags = resolution.tags;
    if (links.isEmpty && tags.isEmpty) return;

    var updated = source;
    for (final decision in links) {
      updated = linkMentionInline(updated, decision.mention, decision.target!);
    }
    updated = updateNoteTags(updated, add: tags);
    if (updated == source) return;
    var applied = false;
    final saved = await workspace.mutateNote(path, (current) {
      if (!identical(vault, v) ||
          note == path ||
          _enrichRevision != navigation ||
          current != source) {
        return current;
      }
      applied = true;
      return updated;
    });
    if (!saved || !applied) return;
    final device = vaultRegistry?.deviceId;
    if (device != null) {
      final at = DateTime.now().toUtc().toIso8601String();
      await _appendEnrichLedger(v, enrichFeedbackDir, device, [
        for (final decision in links)
          EnrichFeedback(
            surface: decision.mention.surface,
            entity: decision.target!.id,
            accepted: true,
            note: path,
            at: at,
            proposedBy: 'auto',
          ),
        for (final tag in tags)
          EnrichFeedback(
            surface: tag,
            entity: enrichTagEntity(tag),
            accepted: true,
            note: path,
            at: at,
            proposedBy: 'auto',
          ),
      ]);
    }
    final file = enrichMentionsPath(path);
    final latest = await _readMentions(v, path);
    if (latest == null || latest.contentSha != mentions.contentSha) return;
    final json = (jsonDecode(await v.storage.readText(file)) as Map)
        .cast<String, Object?>();
    json['content_sha'] = enrichContentSha(updated);
    await v.storage.writeText(file, '${jsonEncode(json)}\n');
  }

  Future<void> _refreshEnrichment() async {
    final v = vault;
    final currentIndex = index;
    final currentIndexRevision = workspace.indexRevision;
    if (v == null || currentIndex == null) return;
    final path = note;
    final isDay = path != null && path.startsWith('daily/');
    if (!isDay) {
      if (_enrichDecisions != null) _rebuild(() => _enrichDecisions = null);
      return;
    }
    final clock = Stopwatch()..start();
    try {
      final memory = await _enrichMemory(v, currentIndex);
      final memoryMs = clock.elapsedMilliseconds;
      if (workspace.indexRevision != currentIndexRevision) return;
      final view = await _applyEnrichment(
        path,
        memory,
        currentIndex,
        currentIndexRevision,
      );
      _enrichTrace(
        '$path decisions=${view.decisions.length} '
        'tags=${view.tags.length} markers=${view.markers.length} '
        'memoryMs=$memoryMs '
        'ms=${clock.elapsedMilliseconds}',
      );
      if (!mounted ||
          vault != v ||
          note != path ||
          workspace.indexRevision != currentIndexRevision) {
        return;
      }
      _rebuild(() => _enrichDecisions = (path, view));
    } catch (error) {
      // Enrichment is advisory: never break opening a note.
      _enrichTrace('$path error $error');
    }
  }

  /// Rebuilt at most every 10 minutes or after a decision: ~30 ms on a Mac
  /// for 10k notes, several times that on a phone, and index revisions
  /// arrive on every save while the user types in the day note. Priors
  /// barely move between saves.
  // ponytail: time-based staleness; key on entity/link changes if new pages
  // must resolve within the 10 minutes.
  /// App-storage vaults are unreadable off a release build; logcat is the
  /// only way to see what enrichment decided on a phone.
  void _enrichTrace(String message) {
    // ignore: avoid_print
    print('TYLOG_ENRICH $message');
  }

  Future<EnrichMemory> _enrichMemory(Vault v, VaultIndex currentIndex) async {
    final currentIndexRevision = workspace.indexRevision;
    final cached = _enrichMemoryCache;
    if (cached != null &&
        identical(cached.$1, v) &&
        cached.$2 == currentIndexRevision &&
        DateTime.now().difference(cached.$3) < const Duration(minutes: 10)) {
      return cached.$4;
    }
    final events = await loadEnrichFeedback(v.storage);
    _enrichShown.addAll(
      (await loadEnrichShown(
        v.storage,
      )).map((e) => (v, e.note, e.surface, e.entity)),
    );
    final memory = await compute(_buildEnrichMemory, (currentIndex, events));
    _enrichMemoryCache = (v, currentIndexRevision, DateTime.now(), memory);
    return memory;
  }

  Future<EnrichMentions?> _readMentions(Vault v, String path) async {
    final file = enrichMentionsPath(path);
    try {
      if (!await v.storage.exists(file)) return null;
      return EnrichMentions.tryParse(
        jsonDecode(await v.storage.readText(file)),
      );
    } catch (_) {
      return null;
    }
  }

  /// Returns suggestions only when they match the current note text.
  Future<_EnrichView> _applyEnrichment(
    String path,
    EnrichMemory memory,
    VaultIndex currentIndex,
    int currentIndexRevision,
  ) async {
    const none = _noEnrich;
    final v = vault;
    final ref = currentIndex.notesByPath[path];
    if (v == null || ref == null) return none;
    final mentions = await _readMentions(v, path);
    if (mentions == null) {
      _enrichTrace('$path no-mentions');
      return none;
    }
    final source = path == note
        ? workspace.source
        : await v.storage.readText(path);
    // Index revisions arrive every sync poll; most change nothing here.
    final memoKey = (
      path,
      source,
      mentions.contentSha,
      memory,
      currentIndexRevision,
    );
    if (_enrichMemo case (final key, final result) when key == memoKey) {
      return result;
    }
    if (enrichContentSha(source) != mentions.contentSha) {
      _enrichTrace('$path edited-since-extraction');
      return none;
    }
    final resolution = await compute(_resolveEnrichDay, (
      mentions,
      ref,
      memory,
      currentIndex,
      source,
    ));
    final _EnrichView result = (
      decisions: resolution.decisions,
      tags: resolution.tags,
      markers: resolution.markers,
      loans: resolution.loans,
      source: source,
    );
    _enrichMemo = (memoKey, result);
    return result;
  }

  Future<Map<String, _EnrichView>> _applyEnrichmentPage(
    List<String> paths,
    EnrichMemory memory,
    VaultIndex currentIndex,
    int currentIndexRevision,
  ) async {
    final results = <String, _EnrichView>{};
    final pending = <_EnrichPageWork>[];
    for (final path in paths) {
      try {
        final ref = currentIndex.notesByPath[path];
        final v = vault;
        if (v == null || ref == null) continue;
        final mentions = await _readMentions(v, path);
        if (mentions == null) continue;
        final source = path == note
            ? workspace.source
            : await v.storage.readText(path);
        if (enrichContentSha(source) != mentions.contentSha) continue;
        final memoKey = (
          path,
          source,
          mentions.contentSha,
          memory,
          currentIndexRevision,
        );
        if (_enrichMemo case (final key, final result) when key == memoKey) {
          results[path] = result;
        } else {
          pending.add((
            path: path,
            ref: ref,
            source: source,
            mentions: mentions,
          ));
        }
      } catch (error) {
        _enrichTrace('$path error $error');
      }
    }
    if (pending.isEmpty) return results;
    late final List<EnrichDayResolution> resolutions;
    try {
      resolutions = await compute(_resolveEnrichPage, (
        pending,
        memory,
        currentIndex,
      ));
    } catch (error) {
      _enrichTrace('incoming page resolution error $error');
      for (final work in pending) {
        try {
          results[work.path] = await _applyEnrichment(
            work.path,
            memory,
            currentIndex,
            currentIndexRevision,
          );
        } catch (error) {
          _enrichTrace('${work.path} error $error');
        }
      }
      return results;
    }
    for (var i = 0; i < pending.length; i++) {
      final work = pending[i];
      final resolution = resolutions[i];
      final view = (
        decisions: resolution.decisions,
        tags: resolution.tags,
        markers: resolution.markers,
        loans: resolution.loans,
        source: work.source,
      );
      final memoKey = (
        work.path,
        work.source,
        work.mentions.contentSha,
        memory,
        currentIndexRevision,
      );
      _enrichMemo = (memoKey, view);
      results[work.path] = view;
    }
    return results;
  }

  Future<void> _recordEnrichFeedback(
    EnrichMention mention,
    String entity, {
    required String path,
    required bool accepted,
  }) async {
    final v = vault;
    final device = vaultRegistry?.deviceId;
    final currentIndex = index;
    if (v == null || device == null || currentIndex == null) {
      return;
    }
    final ref = currentIndex.notesByPath[path];
    final memory = await _enrichMemory(v, currentIndex);
    final mentions = await _readMentions(v, path);
    final event = EnrichFeedback(
      surface: mention.surface,
      entity: entity,
      accepted: accepted,
      note: path,
      at: DateTime.now().toUtc().toIso8601String(),
      proposedBy: mentions?.model == null ? 'llm' : 'llm:${mentions!.model}',
      context: ref == null
          ? const []
          : enrichFeatures(ref, memory.entityIdByTarget).toList(),
    );
    await _appendEnrichLedger(v, enrichFeedbackDir, device, [event]);
    final cache = _enrichMemoryCache;
    if (cache != null &&
        identical(cache.$1, v) &&
        cache.$2 == workspace.indexRevision) {
      cache.$4.addFeedback(event);
      _enrichMemo = null;
    }
  }

  Future<void> _recordEnrichShown(
    Vault v,
    String path,
    _EnrichView view,
    EnrichMemory memory,
  ) async {
    final device = vaultRegistry?.deviceId;
    if (device == null) return;
    final ref = index?.notesByPath[path];
    final offers = [
      for (final d in view.decisions)
        if (d.status == EnrichStatus.review || d.status == EnrichStatus.propose)
          (d.mention.surface, d.target?.id ?? ''),
      for (final m in view.markers) (m.text, enrichMarkerEntity(m.marker.id)),
      for (final offer in view.loans) (offer.ledgerSurface, enrichLoanEntity),
    ];
    final events = <EnrichFeedback>[];
    for (final (surface, entity) in offers) {
      if (!_enrichShown.add((v, path, surface, entity))) continue;
      events.add(
        EnrichFeedback(
          surface: surface,
          entity: entity,
          accepted: false,
          shown: true,
          note: path,
          at: DateTime.now().toUtc().toIso8601String(),
          context: ref == null
              ? const []
              : enrichFeatures(ref, memory.entityIdByTarget).toList(),
        ),
      );
    }
    if (events.isNotEmpty) {
      await _appendEnrichLedger(v, enrichShownDir, device, events);
    }
  }

  Future<void> _appendEnrichLedger(
    Vault v,
    String directory,
    String device,
    List<EnrichFeedback> events,
  ) {
    // Keep ledger events in their original order.
    return _enrichLedgerWrite = _enrichLedgerWrite.then((_) async {
      try {
        final ledger = '$directory/$device.jsonl';
        final error = await _enrichRetry.append(ledger, events, (event) async {
          await v.storage.createDirectory(directory);
          await v.storage.appendBytes(
            ledger,
            utf8.encode('${jsonEncode(event)}\n'),
          );
        });
        if (error != null) throw error;
      } catch (error) {
        debugPrint('Could not save enrichment feedback: $error');
        if (mounted && vault == v) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Could not save enrichment feedback: $error'),
            ),
          );
        }
      }
    });
  }

  Future<void> _refreshEnrichDay(String path) async {
    if (path == note) await _refreshEnrichment();
  }

  Future<void> _acceptEnrich(
    String path,
    EnrichMention mention,
    NoteRef target,
  ) async {
    final v = vault;
    if (v == null) return;
    // The new or renamed page must be in the memory for the next pass.
    _enrichMemoryCache = null;
    await _recordEnrichFeedback(mention, target.id, path: path, accepted: true);
    final mentions = await _readMentions(v, path);
    final source = path == note
        ? workspace.source
        : await v.storage.readText(path);
    if (mentions != null && enrichContentSha(source) == mentions.contentSha) {
      final linked = linkMentionInline(source, mention, target);
      // Only over the text we linked: anything typed since wins.
      if (linked != source &&
          await workspace.mutateNote(
            path,
            (current) => current == source ? linked : current,
          ) &&
          (path != note || workspace.source == linked)) {
        // Same lines, new text: move the mentions file along so the worker
        // does not pay a model call to rediscover what the user just did.
        final file = enrichMentionsPath(path);
        final json = (jsonDecode(await v.storage.readText(file)) as Map)
            .cast<String, Object?>();
        json['content_sha'] = enrichContentSha(linked);
        await v.storage.writeText(file, '${jsonEncode(json)}\n');
      }
    }
    // Learn the name itself: "Катя" becomes an alias of her page.
    final names = {
      for (final name in [target.title, target.id, ...target.aliases])
        enrichKey(name),
    };
    if (target.path != note && !names.contains(enrichKey(mention.surface))) {
      await workspace.mutateNote(target.path, (source) {
        final current = NoteMetadataDraft.fromNote(
          scanNote(target.path, source),
        );
        return replaceNoteHeader(
          source,
          NoteMetadataDraft(
            id: current.id,
            title: current.title,
            kind: current.kind,
            project: current.project,
            date: current.date,
            tags: current.tags,
            aliases: [...current.aliases, mention.surface],
            properties: current.properties,
          ),
        );
      });
    }
    await _refreshEnrichDay(path);
    unawaited(workspace.refreshIndex(always: true));
  }

  Future<void> _rejectEnrich(
    String path,
    EnrichMention mention,
    NoteRef target,
  ) async {
    await _recordEnrichFeedback(
      mention,
      target.id,
      path: path,
      accepted: false,
    );
    await _refreshEnrichDay(path);
  }

  Future<void> _ignoreEnrich(String path, EnrichMention mention) async {
    await _recordEnrichFeedback(
      mention,
      enrichIgnoreEntity,
      path: path,
      accepted: false,
    );
    await _refreshEnrichDay(path);
  }

  Future<void> _acceptEnrichTag(String path, String tag) async {
    await _recordEnrichFeedback(
      EnrichMention(surface: tag, type: 'topic', line: 0),
      enrichTagEntity(tag),
      path: path,
      accepted: true,
    );
    await _editTagsKeepingMentions(
      path,
      (source) => updateNoteTags(source, add: [tag]),
    );
    await _refreshEnrichDay(path);
    unawaited(workspace.refreshIndex(always: true));
  }

  /// A header tag edit is the user's own answer, not new text: re-stamp the
  /// mentions file so the day's other suggestions stay instead of waiting for
  /// the worker to re-read an "edited" day.
  Future<void> _editTagsKeepingMentions(
    String path,
    String Function(String source) edit,
  ) async {
    final v = vault;
    if (v == null) return;
    final before = path == note
        ? workspace.source
        : await v.storage.readText(path);
    final mentions = await _readMentions(v, path);
    final after = edit(before);
    if (after == before ||
        !await workspace.mutateNote(
          path,
          (current) => current == before ? after : edit(current),
        )) {
      return;
    }
    if (mentions == null || enrichContentSha(before) != mentions.contentSha) {
      return;
    }
    final file = enrichMentionsPath(path);
    final json = (jsonDecode(await v.storage.readText(file)) as Map)
        .cast<String, Object?>();
    json['content_sha'] = enrichContentSha(after);
    await v.storage.writeText(file, '${jsonEncode(json)}\n');
  }

  Future<void> _rejectEnrichTag(String path, String tag) async {
    await _recordEnrichFeedback(
      EnrichMention(surface: tag, type: 'topic', line: 0),
      enrichTagEntity(tag),
      path: path,
      accepted: false,
    );
    await _editTagsKeepingMentions(
      path,
      (source) => updateNoteTags(source, remove: tag),
    );
    await _refreshEnrichDay(path);
  }

  /// Files the line under the marker page (the user's own convention, e.g.
  /// fixit) and remembers it; the line text goes to the ledger so the worker
  /// can learn from it.
  Future<void> _acceptEnrichMarker(String path, EnrichMarkerOffer offer) async {
    final v = vault;
    if (v == null) return;
    await _recordEnrichFeedback(
      EnrichMention(surface: offer.text, type: 'topic', line: offer.line),
      enrichMarkerEntity(offer.marker.id),
      path: path,
      accepted: true,
    );
    final source = path == note
        ? workspace.source
        : await v.storage.readText(path);
    final mentions = await _readMentions(v, path);
    final marked = markLine(source, offer.line, offer.marker);
    if (marked != source &&
        await workspace.mutateNote(
          path,
          (current) => current == source ? marked : current,
        ) &&
        (path != note || workspace.source == marked) &&
        mentions != null &&
        enrichContentSha(source) == mentions.contentSha) {
      // Same lines: keep the worker from re-reading what the user just filed.
      final file = enrichMentionsPath(path);
      final json = (jsonDecode(await v.storage.readText(file)) as Map)
          .cast<String, Object?>();
      json['content_sha'] = enrichContentSha(marked);
      await v.storage.writeText(file, '${jsonEncode(json)}\n');
    }
    await _refreshEnrichDay(path);
  }

  Future<void> _rejectEnrichMarker(String path, EnrichMarkerOffer offer) async {
    await _recordEnrichFeedback(
      EnrichMention(surface: offer.text, type: 'topic', line: offer.line),
      enrichMarkerEntity(offer.marker.id),
      path: path,
      accepted: false,
    );
    await _refreshEnrichDay(path);
  }

  Future<void> _acceptEnrichLoan(String path, EnrichLoanOffer offer) async {
    final v = vault;
    if (v == null) return;
    await _recordEnrichFeedback(
      EnrichMention(
        surface: offer.ledgerSurface,
        type: 'topic',
        line: offer.line,
      ),
      enrichLoanEntity,
      path: path,
      accepted: true,
    );
    final source = path == note
        ? workspace.source
        : await v.storage.readText(path);
    final mentions = await _readMentions(v, path);
    final tracked = trackAsLoan(
      source,
      offer,
      loanTaskId(index?.notesByPath[path]?.id ?? path, offer),
      DateTime.now(),
    );
    if (tracked != source &&
        await workspace.mutateNote(
          path,
          (current) => current == source ? tracked : current,
        ) &&
        (path != note || workspace.source == tracked) &&
        mentions != null &&
        enrichContentSha(source) == mentions.contentSha) {
      final file = enrichMentionsPath(path);
      final json = (jsonDecode(await v.storage.readText(file)) as Map)
          .cast<String, Object?>();
      json['content_sha'] = enrichContentSha(tracked);
      await v.storage.writeText(file, '${jsonEncode(json)}\n');
    }
    await _refreshEnrichDay(path);
  }

  Future<void> _rejectEnrichLoan(String path, EnrichLoanOffer offer) async {
    await _recordEnrichFeedback(
      EnrichMention(
        surface: offer.ledgerSurface,
        type: 'topic',
        line: offer.line,
      ),
      enrichLoanEntity,
      path: path,
      accepted: false,
    );
    await _refreshEnrichDay(path);
  }

  /// One decision at a time: a second tap while the first is still writing
  /// recorded the same accept twice.
  Future<void> _enrichOnce(Future<void> Function() action) async {
    if (_enrichBusy) return;
    _enrichBusy = true;
    try {
      await action();
    } finally {
      _enrichBusy = false;
    }
  }

  Future<void> _createFromEnrich(String path, EnrichMention mention) async {
    final created = await _createEntity(
      initialName: mention.surface,
      initialKind: mention.type,
    );
    if (created != null) await _acceptEnrich(path, mention, created);
  }
}

extension _EnrichIncoming on _HomeScreenState {
  Future<void> _showEnrichIncoming({String? day}) async {
    final v = vault;
    final currentIndex = index;
    if (v == null || currentIndex == null) return;
    List<String>? paths;
    var cursor = 0;
    var more = false;
    var audioOffset = 0;
    var ocrOffset = 0;
    List<Decision>? decisionSnapshot;
    Object? loadError;
    final views = <String, _EnrichView>{};
    final decidedClusters = <String>{};
    final decidedFills = <String>{};
    Future<Map<String, _EnrichView>> load({
      bool next = false,
      String? refreshPath,
    }) async {
      final indexRevision = workspace.indexRevision;
      paths ??=
          currentIndex.notesByPath.keys
              .where(
                (path) =>
                    path.startsWith('daily/') && (day == null || day == path),
              )
              .toList()
            ..sort((a, b) => b.compareTo(a));
      final page = <String>[];
      if (next) {
        final end = (cursor + 7).clamp(0, paths!.length);
        page.addAll(paths!.sublist(cursor, end));
        cursor = end;
      }
      if (refreshPath != null) page.add(refreshPath);
      more = cursor < paths!.length;
      final eligiblePage = page
          .where((path) => currentIndex.notesByPath.containsKey(path))
          .toList();
      if (eligiblePage.isEmpty) {
        return {
          for (final path
              in views.keys.toList()..sort((a, b) => b.compareTo(a)))
            path: views[path]!,
        };
      }
      final memory = await _enrichMemory(v, currentIndex);
      if (workspace.indexRevision != indexRevision) return {};
      final pageViews = await _applyEnrichmentPage(
        eligiblePage,
        memory,
        currentIndex,
        indexRevision,
      );
      if (workspace.indexRevision != indexRevision) return {};
      for (final path in eligiblePage) {
        views.remove(path);
        final view = pageViews[path] ?? _noEnrich;
        if (view.decisions.isEmpty &&
            view.tags.isEmpty &&
            view.markers.isEmpty &&
            view.loans.isEmpty) {
          continue;
        }
        views[path] = view;
        await _recordEnrichShown(v, path, view, memory);
      }
      final ordered = views.keys.toList()..sort((a, b) => b.compareTo(a));
      return {for (final path in ordered) path: views[path]!};
    }

    Future<
      (
        Map<String, _EnrichView>,
        List<OcrReviewRow>,
        List<AudioProposal>,
        List<HealthFinding>,
        List<Map<String, dynamic>>,
        List<FillDraft>,
      )
    >
    loadQueue({bool next = false, String? refreshPath}) async {
      try {
        final mentionsFuture = load(next: next, refreshPath: refreshPath);
        final decisionsFuture = decisionSnapshot == null
            ? loadDecisions(v.storage, includeEnrichment: false)
            : Future.value(decisionSnapshot!);
        final mentions = await mentionsFuture;
        final decisions = await decisionsFuture;
        decisionSnapshot ??= decisions;
        final proposalRows = <Map<String, dynamic>>[];
        try {
          final proposalJson =
              jsonDecode(
                    await v.storage.readText('_system/clusters/proposals.json'),
                  )
                  as Map;
          for (final row in (proposalJson['changes'] as List? ?? const [])) {
            if (row is Map &&
                const {'rename', 'merge', 'split'}.contains(row['kind']) &&
                row['id'] is String &&
                !decidedClusters.contains(row['id'])) {
              proposalRows.add(Map<String, dynamic>.from(row));
            }
          }
        } catch (_) {}
        if (day != null) {
          return (
            mentions,
            <OcrReviewRow>[],
            <AudioProposal>[],
            <HealthFinding>[],
            proposalRows,
            <FillDraft>[],
          );
        }
        final queue = await Future.wait<Object>([
          loadOcrReviewRows(
            v.storage,
            workspace.mounts.map((mount) => mount.id),
            decisions,
            offset: ocrOffset,
            summary: _actionableSidecars,
          ),
          loadAudioProposals(
            v.storage,
            decisions,
            offset: audioOffset,
            summary: _actionableSidecars,
          ),
          loadHealthFindings(v.storage),
          loadFillDrafts(v.storage, decisions),
        ]);
        return (
          mentions,
          queue[0] as List<OcrReviewRow>,
          queue[1] as List<AudioProposal>,
          queue[2] as List<HealthFinding>,
          proposalRows,
          queue[3] as List<FillDraft>,
        );
      } catch (error) {
        loadError = error;
        return (
          <String, _EnrichView>{},
          <OcrReviewRow>[],
          <AudioProposal>[],
          <HealthFinding>[],
          <Map<String, dynamic>>[],
          <FillDraft>[],
        );
      }
    }

    var future = loadQueue(next: true);
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) {
          void decide(
            Future<void> Function() action, {
            String? path,
            Decision? decision,
          }) {
            unawaited(
              _enrichOnce(() async {
                await action();
                if (decision case final row? when row.device.isNotEmpty) {
                  decisionSnapshot = [...?decisionSnapshot, row];
                }
                if (context.mounted) {
                  setSheetState(() {
                    future = loadQueue(refreshPath: path);
                  });
                }
              }),
            );
          }

          return SafeArea(
            child: SizedBox(
              height: MediaQuery.sizeOf(context).height * .75,
              child:
                  FutureBuilder<
                    (
                      Map<String, _EnrichView>,
                      List<OcrReviewRow>,
                      List<AudioProposal>,
                      List<HealthFinding>,
                      List<Map<String, dynamic>>,
                      List<FillDraft>,
                    )
                  >(
                    future: future,
                    builder: (context, snapshot) {
                      final views = snapshot.data?.$1;
                      final rows = snapshot.data?.$2 ?? <OcrReviewRow>[];
                      final audio = snapshot.data?.$3 ?? <AudioProposal>[];
                      final health = snapshot.data?.$4 ?? <HealthFinding>[];
                      final fills = (snapshot.data?.$6 ?? <FillDraft>[])
                          .where((d) => !decidedFills.contains(d.item))
                          .toList();
                      final clusters =
                          snapshot.data?.$5 ?? <Map<String, dynamic>>[];
                      final bookings = day == null
                          ? oltIncomingOnDay(
                              _oltCache,
                              _oltDecided,
                              isoDay(DateTime.now()),
                              pending: true,
                            ).where((note) => note.kind == 'booking').toList()
                          : <NoteRef>[];
                      return ListView(
                        children: [
                          ListTile(
                            title: const Text('Incoming'),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  tooltip: 'Recluster now',
                                  icon: const Icon(Icons.hub),
                                  onPressed: () async {
                                    try {
                                      final currentIndex = index;
                                      if (currentIndex == null) {
                                        throw StateError(
                                          'Vault index is not ready',
                                        );
                                      }
                                      await runClusterStep(
                                        v.storage,
                                        currentIndex,
                                        now: DateTime.now(),
                                      );
                                      await workspace.reloadClusterSnapshot();
                                      await workspace.refreshDerived();
                                      if (context.mounted) {
                                        setSheetState(() {
                                          future = loadQueue();
                                        });
                                      }
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          const SnackBar(
                                            content: Text('Clusters updated'),
                                          ),
                                        );
                                      }
                                    } catch (error) {
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          SnackBar(
                                            content: Text(
                                              'Cluster update failed: $error',
                                            ),
                                          ),
                                        );
                                      }
                                    }
                                  },
                                ),
                                IconButton(
                                  tooltip: 'Run suggestions now',
                                  icon: const Icon(Icons.refresh),
                                  onPressed: () async {
                                    await v.storage.writeText(
                                      '_system/enrich/run-request.json',
                                      '${jsonEncode({'requested_at': DateTime.now().toUtc().toIso8601String()})}\n',
                                    );
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            'Suggestions will update in a few minutes',
                                          ),
                                        ),
                                      );
                                    }
                                  },
                                ),
                              ],
                            ),
                          ),
                          for (final change in clusters)
                            ListTile(
                              title: Text(clusterChangeTitle(change)),
                              subtitle: Text(
                                clusterChangeSubtitle(
                                  change,
                                  workspace.clusterSnapshot,
                                ),
                              ),
                              trailing: Wrap(
                                children: [
                                  TextButton(
                                    onPressed: () => decide(() async {
                                      final device = vaultRegistry?.deviceId;
                                      if (device == null) return;
                                      await _appendIncomingDecision(
                                        v,
                                        device,
                                        Decision(
                                          at: DateTime.now().toIso8601String(),
                                          device: device,
                                          item: change['id'] as String,
                                          source: 'clusters',
                                          action: 'accepted',
                                          target: change['id'] as String,
                                        ),
                                      );
                                      decidedClusters.add(
                                        change['id'] as String,
                                      );
                                    }),
                                    child: const Text('Accept'),
                                  ),
                                  TextButton(
                                    onPressed: () => decide(() async {
                                      final device = vaultRegistry?.deviceId;
                                      if (device == null) return;
                                      await _appendIncomingDecision(
                                        v,
                                        device,
                                        Decision(
                                          at: DateTime.now().toIso8601String(),
                                          device: device,
                                          item: change['id'] as String,
                                          source: 'clusters',
                                          action: 'rejected',
                                          target: change['id'] as String,
                                        ),
                                      );
                                      decidedClusters.add(
                                        change['id'] as String,
                                      );
                                    }),
                                    child: const Text('Reject'),
                                  ),
                                ],
                              ),
                            ),
                          if (loadError != null || snapshot.hasError)
                            ListTile(
                              title: const Text('Could not load suggestions'),
                              trailing: TextButton(
                                onPressed: () => setSheetState(() {
                                  decisionSnapshot = null;
                                  loadError = null;
                                  future = loadQueue();
                                }),
                                child: const Text('Try again'),
                              ),
                            )
                          else if (views == null)
                            const Center(child: CircularProgressIndicator())
                          else if (views.isEmpty &&
                              rows.isEmpty &&
                              audio.isEmpty &&
                              fills.isEmpty &&
                              health.isEmpty &&
                              bookings.isEmpty)
                            ListTile(
                              title: Text(
                                more
                                    ? 'No suggestions in these days'
                                    : 'No suggestions',
                              ),
                            ),
                          for (final type in reviewQueueTypes) ...[
                            if (type == ReviewQueueType.health &&
                                health.isNotEmpty) ...[
                              ListTile(title: Text(type.label)),
                              for (final finding in health)
                                ListTile(
                                  title: Text(finding.path),
                                  subtitle: Text(finding.code),
                                  trailing: Wrap(
                                    children: [
                                      TextButton(
                                        onPressed: () async {
                                          Navigator.of(context).pop();
                                          await _openNote(finding.path);
                                        },
                                        child: const Text('Open'),
                                      ),
                                      TextButton(
                                        onPressed: () async {
                                          Navigator.of(context).pop();
                                          if (await _openNote(finding.path) &&
                                              mounted) {
                                            _setEditorMode('source');
                                          }
                                        },
                                        child: const Text('Open Source'),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                            if (type == ReviewQueueType.mentions &&
                                views != null &&
                                views.isNotEmpty) ...[
                              ListTile(title: Text(type.label)),
                              for (final entry in views.entries) ...[
                                ListTile(
                                  title: Text(
                                    entry.key
                                        .split('/')
                                        .last
                                        .replaceFirst('.typ', ''),
                                  ),
                                ),
                                EnrichReview(
                                  decisions: entry.value.decisions,
                                  source: entry.value.source,
                                  pages: currentIndex.notesByPath.values
                                      .toList(),
                                  tags: entry.value.tags,
                                  markers: entry.value.markers,
                                  loans: entry.value.loans,
                                  onAcceptLoan: (offer) => decide(
                                    () => _acceptEnrichLoan(entry.key, offer),
                                    path: entry.key,
                                  ),
                                  onRejectLoan: (offer) => decide(
                                    () => _rejectEnrichLoan(entry.key, offer),
                                    path: entry.key,
                                  ),
                                  onAcceptMarker: (offer) => decide(
                                    () => _acceptEnrichMarker(entry.key, offer),
                                    path: entry.key,
                                  ),
                                  onRejectMarker: (offer) => decide(
                                    () => _rejectEnrichMarker(entry.key, offer),
                                    path: entry.key,
                                  ),
                                  onRejectTag: (tag) => decide(
                                    () => _rejectEnrichTag(entry.key, tag),
                                    path: entry.key,
                                  ),
                                  onAcceptTag: (tag) => decide(
                                    () => _acceptEnrichTag(entry.key, tag),
                                    path: entry.key,
                                  ),
                                  appliedTags:
                                      currentIndex.notesByPath[entry.key]?.tags
                                          .toSet() ??
                                      const {},
                                  onAccept: (mention, target) => decide(
                                    () => _acceptEnrich(
                                      entry.key,
                                      mention,
                                      target,
                                    ),
                                    path: entry.key,
                                  ),
                                  onReject: (mention, target) => decide(
                                    () => _rejectEnrich(
                                      entry.key,
                                      mention,
                                      target,
                                    ),
                                    path: entry.key,
                                  ),
                                  onIgnore: (mention) => decide(
                                    () => _ignoreEnrich(entry.key, mention),
                                    path: entry.key,
                                  ),
                                  onCreate: (mention) => decide(
                                    () => _createFromEnrich(entry.key, mention),
                                    path: entry.key,
                                  ),
                                ),
                              ],
                            ],
                            if (type == ReviewQueueType.audio &&
                                audio.isNotEmpty) ...[
                              ListTile(title: Text(type.label)),
                              for (final proposal in audio)
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: kSpace16,
                                    vertical: kSpace8,
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(proposal.text),
                                      Text(
                                        '${proposal.note}${proposal.date == null ? '' : ' · ${proposal.date}'}',
                                        style: Theme.of(
                                          context,
                                        ).textTheme.bodySmall,
                                      ),
                                      Row(
                                        children: [
                                          ActionChip(
                                            label: Text(
                                              proposal.kind == 'agenda'
                                                  ? 'Add to agenda'
                                                  : 'Add task',
                                            ),
                                            onPressed: () => decide(
                                              () => _decideAudioProposal(
                                                proposal,
                                                true,
                                              ),
                                              decision: Decision(
                                                at: DateTime.now()
                                                    .toIso8601String(),
                                                device:
                                                    vaultRegistry?.deviceId ??
                                                    '',
                                                item: proposal.id,
                                                source: proposal.source,
                                                action: 'accepted',
                                              ),
                                            ),
                                          ),
                                          IconButton(
                                            tooltip: 'Reject audio proposal',
                                            icon: const Icon(Icons.close),
                                            onPressed: () => decide(
                                              () => _decideAudioProposal(
                                                proposal,
                                                false,
                                              ),
                                              decision: Decision(
                                                at: DateTime.now()
                                                    .toIso8601String(),
                                                device:
                                                    vaultRegistry?.deviceId ??
                                                    '',
                                                item: proposal.id,
                                                source: proposal.source,
                                                action: 'rejected',
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              if (audio.length == 20)
                                TextButton(
                                  onPressed: () => setSheetState(() {
                                    audioOffset += 20;
                                    future = loadQueue();
                                  }),
                                  child: const Text('Show older audio'),
                                ),
                            ],
                            if (type == ReviewQueueType.fill &&
                                fills.isNotEmpty) ...[
                              ListTile(title: Text(type.label)),
                              for (final draft in fills)
                                ListTile(
                                  key: ValueKey('fill-${draft.item}'),
                                  title: Text(
                                    draft.status == null
                                        ? 'Info for ${draft.title}'
                                        : 'Nothing reliable found for '
                                              '${draft.title}',
                                  ),
                                  subtitle: Text(
                                    draft.status != null
                                        ? (draft.status == 'mismatch'
                                              ? 'Sources were about something else'
                                              : 'No public sources found')
                                        : [
                                            for (final entry
                                                in draft.properties.entries)
                                              '${entry.key}: ${entry.value}',
                                            for (final entry
                                                in draft.sections.entries)
                                              '${entry.key}: ${entry.value}',
                                          ].join('\n'),
                                    maxLines: 6,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  trailing: Wrap(
                                    children: [
                                      if (draft.status == null)
                                        TextButton(
                                          onPressed: () => decide(() async {
                                            await _decideFill(draft, true);
                                            decidedFills.add(draft.item);
                                          }),
                                          child: const Text('Add to page'),
                                        ),
                                      TextButton(
                                        onPressed: () => decide(() async {
                                          await _decideFill(draft, false);
                                          decidedFills.add(draft.item);
                                        }),
                                        child: Text(
                                          draft.status == null
                                              ? 'Reject'
                                              : 'Dismiss',
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                            if (type == ReviewQueueType.ocr &&
                                rows.isNotEmpty) ...[
                              ListTile(title: Text(type.label)),
                              for (final row in rows)
                                ListTile(
                                  title: Text(row.dataset),
                                  subtitle: Text(row.fields),
                                  trailing: Wrap(
                                    children: [
                                      IconButton(
                                        tooltip: 'Accept',
                                        icon: const Icon(Icons.check),
                                        onPressed: () => decide(
                                          () async {
                                            final device =
                                                vaultRegistry?.deviceId;
                                            if (device == null) return;
                                            await _appendIncomingDecision(
                                              v,
                                              device,
                                              Decision(
                                                at: DateTime.now()
                                                    .toIso8601String(),
                                                device: device,
                                                item: row.id,
                                                source: 'ocr',
                                                action: 'accepted',
                                              ),
                                            );
                                          },
                                          decision: Decision(
                                            at: DateTime.now()
                                                .toIso8601String(),
                                            device:
                                                vaultRegistry?.deviceId ?? '',
                                            item: row.id,
                                            source: 'ocr',
                                            action: 'accepted',
                                          ),
                                        ),
                                      ),
                                      IconButton(
                                        tooltip: 'Reject',
                                        icon: const Icon(Icons.close),
                                        onPressed: () => decide(
                                          () async {
                                            final device =
                                                vaultRegistry?.deviceId;
                                            if (device == null) return;
                                            await _appendIncomingDecision(
                                              v,
                                              device,
                                              Decision(
                                                at: DateTime.now()
                                                    .toIso8601String(),
                                                device: device,
                                                item: row.id,
                                                source: 'ocr',
                                                action: 'rejected',
                                              ),
                                            );
                                          },
                                          decision: Decision(
                                            at: DateTime.now()
                                                .toIso8601String(),
                                            device:
                                                vaultRegistry?.deviceId ?? '',
                                            item: row.id,
                                            source: 'ocr',
                                            action: 'rejected',
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              if (rows.length == 20)
                                TextButton(
                                  onPressed: () => setSheetState(() {
                                    ocrOffset += 20;
                                    future = loadQueue();
                                  }),
                                  child: const Text('Show older OCR'),
                                ),
                            ],
                            if (type == ReviewQueueType.bookings &&
                                bookings.isNotEmpty) ...[
                              ListTile(title: Text(type.label)),
                              for (final booking in bookings)
                                ListTile(
                                  title: Text(booking.title),
                                  subtitle: Text(
                                    '${booking.date ?? ''} · ${booking.properties['places'] ?? ''}',
                                  ),
                                  trailing: Wrap(
                                    children: [
                                      IconButton(
                                        tooltip: 'Accept booking',
                                        icon: const Icon(Icons.check),
                                        onPressed: () => decide(
                                          () => _decideIncoming(
                                            booking,
                                            'accepted',
                                          ),
                                        ),
                                      ),
                                      IconButton(
                                        tooltip: 'Reject booking',
                                        icon: const Icon(Icons.close),
                                        onPressed: () => decide(
                                          () => _decideIncoming(
                                            booking,
                                            'rejected',
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ],
                          if (views != null && more)
                            TextButton(
                              onPressed:
                                  snapshot.connectionState ==
                                      ConnectionState.done
                                  ? () => setSheetState(() {
                                      future = loadQueue(next: true);
                                    })
                                  : null,
                              child: const Text('Show older'),
                            ),
                        ],
                      );
                    },
                  ),
            ),
          );
        },
      ),
    );
  }
}
