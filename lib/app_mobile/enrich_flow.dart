part of '../app_mobile.dart';

/// What the Mentions strip shows for one day.
typedef _EnrichView = ({
  List<EnrichDecision> decisions,
  List<String> tags,
  List<EnrichMarkerOffer> markers,
  String source,
});

const _EnrichView _noEnrich = (
  decisions: [],
  tags: [],
  markers: [],
  source: '',
);

EnrichMemory _buildEnrichMemory((VaultIndex, List<EnrichFeedback>) input) =>
    EnrichMemory.build(input.$1, input.$2);

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
    final lines = source.split('\n');
    final typed = scanNote(path, stripAutoEntities(source)).outgoingLinks;
    final decisions = resolveMentions(mentions, ref, memory);
    final links = [
      for (final decision in decisions)
        if (decision.status == EnrichStatus.linked)
          if (decision.target case final target?
              when !typed.contains(target.id) &&
                  !enrichLinkedOnLine(decision.mention, lines))
            decision,
    ];
    final tags = enrichTags(mentions.keywords, currentIndex, memory: memory);
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
      _rebuild(() => _enrichDecisions = path == null ? null : (path, view));
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
    final decisions = resolveMentions(mentions, ref, memory);
    final tags = enrichTags(mentions.keywords, currentIndex, memory: memory);
    // Links the user typed are theirs: no chip offering to unlink them.
    final typed = scanNote(path, stripAutoEntities(source)).outgoingLinks;
    final lines = source.split('\n');
    final _EnrichView result = (
      decisions: [
        for (final decision in decisions)
          if ((decision.status != EnrichStatus.linked ||
                  !typed.contains(decision.target!.id)) &&
              !enrichLinkedOnLine(decision.mention, lines))
            decision,
      ],
      tags: tags,
      markers: enrichMarkerOffers(mentions, source, memory),
      source: source,
    );
    _enrichMemo = (memoKey, result);
    return result;
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
    final event = EnrichFeedback(
      surface: mention.surface,
      entity: entity,
      accepted: accepted,
      note: path,
      at: DateTime.now().toUtc().toIso8601String(),
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
        await v.storage.createDirectory(directory);
        for (final event in events) {
          await v.storage.appendBytes(
            ledger,
            utf8.encode('${jsonEncode(event)}\n'),
          );
        }
      } catch (_) {}
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

  Future<void> _rejectEnrichTag(String path, String tag) async {
    await _recordEnrichFeedback(
      EnrichMention(surface: tag, type: 'topic', line: 0),
      enrichTagEntity(tag),
      path: path,
      accepted: false,
    );
    await workspace.mutateNote(
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
    Future<Map<String, _EnrichView>> load({
      bool next = false,
      String? refreshPath,
    }) async {
      final indexRevision = workspace.indexRevision;
      final memory = await _enrichMemory(v, currentIndex);
      if (workspace.indexRevision != indexRevision) return {};
      if (paths == null) {
        if (!await v.storage.exists(enrichMentionsDir)) return {};
        final files = await v.storage.list(
          path: enrichMentionsDir,
          recursive: true,
        );
        paths =
            files
                .where((f) => !f.isDirectory && f.path.endsWith('.json'))
                .map(
                  (f) =>
                      '${f.path.substring(enrichMentionsDir.length + 1, f.path.length - 5)}.typ',
                )
                .where(
                  (p) => p.startsWith('daily/') && (day == null || day == p),
                )
                .toList()
              ..sort((a, b) => b.compareTo(a));
      }
      final page = <String>[];
      if (next) {
        final end = (cursor + 7).clamp(0, paths!.length);
        page.addAll(paths!.sublist(cursor, end));
        cursor = end;
      }
      if (refreshPath != null) page.add(refreshPath);
      more = cursor < paths!.length;
      for (final path in page) {
        views.remove(path);
        if (!currentIndex.notesByPath.containsKey(path)) continue;
        try {
          final view = await _applyEnrichment(
            path,
            memory,
            currentIndex,
            indexRevision,
          );
          if (workspace.indexRevision != indexRevision) return {};
          if (view.decisions.isEmpty &&
              view.tags.isEmpty &&
              view.markers.isEmpty) {
            continue;
          }
          views[path] = view;
          await _recordEnrichShown(v, path, view, memory);
        } catch (error) {
          _enrichTrace('$path error $error');
        }
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
      )
    >
    loadQueue({bool next = false, String? refreshPath}) async {
      try {
        final mentions = await load(next: next, refreshPath: refreshPath);
        final decisions = decisionSnapshot ??= await loadDecisions(v.storage);
        return (
          mentions,
          day == null
              ? await loadOcrReviewRows(
                  v.storage,
                  workspace.mounts.map((mount) => mount.id),
                  decisions,
                  offset: ocrOffset,
                  summary: _actionableSidecars,
                )
              : <OcrReviewRow>[],
          day == null
              ? await loadAudioProposals(
                  v.storage,
                  decisions,
                  offset: audioOffset,
                  summary: _actionableSidecars,
                )
              : <AudioProposal>[],
          day == null ? await loadHealthFindings(v.storage) : <HealthFinding>[],
        );
      } catch (error) {
        loadError = error;
        return (
          <String, _EnrichView>{},
          <OcrReviewRow>[],
          <AudioProposal>[],
          <HealthFinding>[],
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
                    )
                  >(
                    future: future,
                    builder: (context, snapshot) {
                      final views = snapshot.data?.$1;
                      final rows = snapshot.data?.$2 ?? <OcrReviewRow>[];
                      final audio = snapshot.data?.$3 ?? <AudioProposal>[];
                      final health = snapshot.data?.$4 ?? <HealthFinding>[];
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
                          const ListTile(title: Text('Incoming')),
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
                                                source: 'audio',
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
                                                source: 'audio',
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
