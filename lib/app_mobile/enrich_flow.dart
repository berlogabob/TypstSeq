part of '../app_mobile.dart';

/// What the Mentions strip shows for one day.
typedef _EnrichView = ({
  List<EnrichDecision> decisions,
  List<String> tags,
  List<EnrichMarkerOffer> markers,
});

const _EnrichView _noEnrich = (decisions: [], tags: [], markers: []);

/// Day-log enrichment in the app: reads the worker's mentions files,
/// resolves them with [EnrichMemory], writes the `// tylog:auto-entities`
/// block, and records the user's decisions in this device's ledger.
extension _EnrichFlow on _HomeScreenState {
  /// Called on every workspace change; does work only when the open note or
  /// the index changed.
  void _queueEnrichRefresh() {
    final key = (vault, note, workspace.indexRevision);
    if (_enrichRevision == key) return;
    _enrichRevision = key;
    unawaited(_refreshEnrichment());
  }

  /// Phones only read: a block written by the Mac and the phone at once is a
  /// sync conflict on a day note, and a conflict pauses all auto-sync. The
  /// phone writes only on the user's own tap.
  bool get _enrichAutoWrite =>
      defaultTargetPlatform != TargetPlatform.android &&
      defaultTargetPlatform != TargetPlatform.iOS;

  Future<void> _refreshEnrichment({bool userAction = false}) async {
    final v = vault;
    final currentIndex = index;
    if (v == null || currentIndex == null) return;
    final path = note;
    // Today is still being written, maybe on another device: a block landing
    // mid-edit is a sync conflict. It gets its block tomorrow, or on a tap.
    final write =
        userAction || (_enrichAutoWrite && path != await v.todayNote());
    final isDay = path != null && path.startsWith('daily/');
    if (_enrichPassVault == v && !isDay) {
      if (_enrichDecisions != null) _rebuild(() => _enrichDecisions = null);
      return;
    }
    final clock = Stopwatch()..start();
    try {
      final memory = await _enrichMemory(v, currentIndex);
      final memoryMs = clock.elapsedMilliseconds;
      if (_enrichPassVault != v) {
        _enrichPassVault = v;
        // ponytail: only the last two weeks of days get blocks written on
        // open; older days get theirs when viewed. A full pass needs a
        // device-local "applied sha" record to stay cheap on SAF.
        final today = DateTime.now();
        for (var i = 1; _enrichAutoWrite && i <= 14; i++) {
          final path = await v.todayNote(today.subtract(Duration(days: i)));
          await _applyEnrichment(path, memory, write: true);
        }
      }
      final view = isDay
          ? await _applyEnrichment(path, memory, write: write)
          : _noEnrich;
      _enrichTrace(
        '$path write=$write decisions=${view.decisions.length} '
        'tags=${view.tags.length} markers=${view.markers.length} '
        'memoryMs=$memoryMs '
        'ms=${clock.elapsedMilliseconds}',
      );
      if (!mounted || vault != v || note != path) return;
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
    final cached = _enrichMemoryCache;
    if (cached != null &&
        identical(cached.$1, v) &&
        DateTime.now().difference(cached.$2) < const Duration(minutes: 10)) {
      return cached.$3;
    }
    final events = await loadEnrichFeedback(v.storage);
    _enrichShown.addAll(
      (await loadEnrichShown(
        v.storage,
      )).map((e) => (v, e.note, e.surface, e.entity)),
    );
    final memory = EnrichMemory.build(currentIndex, events);
    _enrichMemoryCache = (v, DateTime.now(), memory);
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

  /// Rewrites [path]'s block (when [write]) if its mentions were computed
  /// from exactly the text it has now. Returns what the review strip shows.
  Future<_EnrichView> _applyEnrichment(
    String path,
    EnrichMemory memory, {
    required bool write,
  }) async {
    const none = _noEnrich;
    final v = vault;
    final ref = index?.notesByPath[path];
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
    final memoKey = (path, source, mentions.contentSha, memory, write);
    if (_enrichMemo case (final key, final result) when key == memoKey) {
      return result;
    }
    final decisions = resolveMentions(mentions, ref, memory);
    final tags = enrichTags(mentions.keywords, index!, memory: memory);
    String? apply(String current) =>
        enrichContentSha(current) == mentions.contentSha
        ? writeAutoEntities(current, ref, decisions, tags)
        : null;
    final updated = apply(source);
    if (updated == null) {
      _enrichTrace('$path edited-since-extraction');
      return none;
    }
    if (write && updated != source) {
      // Re-checked inside: the user may have typed while we resolved.
      await workspace.mutateNote(path, (current) => apply(current) ?? current);
    }
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
      markers: enrichMarkerOffers(mentions, source, index!, memory),
    );
    // Not after a write: the rewritten note must be looked at again.
    if (!(write && updated != source)) _enrichMemo = (memoKey, result);
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
    _enrichMemoryCache = null;
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
    if (path == note) {
      await _refreshEnrichment(userAction: true);
    } else if (vault != null && index != null) {
      await _applyEnrichment(
        path,
        await _enrichMemory(vault!, index!),
        write: true,
      );
    }
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
    if (!names.contains(enrichKey(mention.surface))) {
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

  Future<void> _rejectEnrichTag(String path, String tag) async {
    await _recordEnrichFeedback(
      EnrichMention(surface: tag, type: 'topic', line: 0),
      enrichTagEntity(tag),
      path: path,
      accepted: false,
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
    // ponytail: newest days first, a page at a time; every day costs two
    // SAF reads and a ledger write on Android.
    var limit = 7;
    var more = false;
    Future<Map<String, _EnrichView>> load() async {
      final memory = await _enrichMemory(v, currentIndex);
      if (!await v.storage.exists(enrichMentionsDir)) return {};
      final files = await v.storage.list(
        path: enrichMentionsDir,
        recursive: true,
      );
      final paths =
          files
              .where((f) => !f.isDirectory && f.path.endsWith('.json'))
              .map(
                (f) =>
                    '${f.path.substring(enrichMentionsDir.length + 1, f.path.length - 5)}.typ',
              )
              .where((p) => p.startsWith('daily/') && (day == null || day == p))
              .toList()
            ..sort((a, b) => b.compareTo(a));
      final views = <String, _EnrichView>{};
      more = false;
      for (final path in paths) {
        if (views.length >= limit) {
          more = true;
          break;
        }
        if (!currentIndex.notesByPath.containsKey(path)) continue;
        try {
          final view = await _applyEnrichment(path, memory, write: false);
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
      return views;
    }

    var future = load();
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) {
          void decide(Future<void> Function() action) {
            unawaited(
              _enrichOnce(() async {
                await action();
                if (context.mounted) {
                  setSheetState(() {
                    future = load();
                  });
                }
              }),
            );
          }

          return SafeArea(
            child: SizedBox(
              height: MediaQuery.sizeOf(context).height * .75,
              child: FutureBuilder<Map<String, _EnrichView>>(
                future: future,
                builder: (context, snapshot) {
                  final views = snapshot.data;
                  return ListView(
                    children: [
                      const ListTile(title: Text('Incoming')),
                      if (snapshot.hasError)
                        const ListTile(
                          title: Text('Could not load suggestions'),
                        )
                      else if (views == null)
                        const Center(child: CircularProgressIndicator())
                      else if (views.isEmpty)
                        const ListTile(title: Text('No suggestions'))
                      else
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
                            tags: entry.value.tags,
                            markers: entry.value.markers,
                            onAcceptMarker: (offer) => decide(
                              () => _acceptEnrichMarker(entry.key, offer),
                            ),
                            onRejectMarker: (offer) => decide(
                              () => _rejectEnrichMarker(entry.key, offer),
                            ),
                            onRejectTag: (tag) =>
                                decide(() => _rejectEnrichTag(entry.key, tag)),
                            onAccept: (mention, target) => decide(
                              () => _acceptEnrich(entry.key, mention, target),
                            ),
                            onReject: (mention, target) => decide(
                              () => _rejectEnrich(entry.key, mention, target),
                            ),
                            onCreate: (mention) => decide(
                              () => _createFromEnrich(entry.key, mention),
                            ),
                          ),
                        ],
                      if (views != null && more)
                        TextButton(
                          onPressed: () => setSheetState(() {
                            limit += 7;
                            future = load();
                          }),
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
