part of '../app_mobile.dart';

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
      final (decisions, tags) = isDay
          ? await _applyEnrichment(path, memory, write: write)
          : (const <EnrichDecision>[], const <String>[]);
      _enrichTrace(
        '$path write=$write decisions=${decisions.length} '
        'tags=${tags.length} memoryMs=$memoryMs '
        'ms=${clock.elapsedMilliseconds}',
      );
      if (!mounted || note != path) return;
      _rebuild(
        () => _enrichDecisions = path == null ? null : (path, decisions, tags),
      );
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
    final events = <EnrichFeedback>[];
    try {
      for (final file in await v.storage.list(path: enrichFeedbackDir)) {
        if (file.isDirectory || !file.path.endsWith('.jsonl')) continue;
        events.addAll(
          EnrichFeedback.parseLedger(await v.storage.readText(file.path)),
        );
      }
    } catch (_) {}
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
  Future<(List<EnrichDecision>, List<String>)> _applyEnrichment(
    String path,
    EnrichMemory memory, {
    required bool write,
  }) async {
    const none = (<EnrichDecision>[], <String>[]);
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
    final memoKey = (path, source, mentions.contentSha, memory);
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
    final result = (
      [
        for (final decision in decisions)
          if (decision.status != EnrichStatus.linked ||
              !typed.contains(decision.target!.id))
            decision,
      ],
      tags,
    );
    // Not after a write: the rewritten note must be looked at again.
    if (!(write && updated != source)) _enrichMemo = (memoKey, result);
    return result;
  }

  Future<void> _recordEnrichFeedback(
    EnrichMention mention,
    String entity, {
    required bool accepted,
  }) async {
    final v = vault;
    final device = vaultRegistry?.deviceId;
    final path = note;
    final currentIndex = index;
    if (v == null || device == null || path == null || currentIndex == null) {
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
    final ledger = '$enrichFeedbackDir/$device.jsonl';
    await v.storage.createDirectory(enrichFeedbackDir);
    final existing = await v.storage.exists(ledger)
        ? await v.storage.readText(ledger)
        : '';
    await v.storage.writeText(ledger, '$existing${jsonEncode(event)}\n');
    _enrichMemoryCache = null;
  }

  Future<void> _acceptEnrich(EnrichMention mention, NoteRef target) async {
    final v = vault;
    final path = note;
    if (v == null || path == null) return;
    await _recordEnrichFeedback(mention, target.id, accepted: true);
    final mentions = await _readMentions(v, path);
    final source = workspace.source;
    if (mentions != null && enrichContentSha(source) == mentions.contentSha) {
      final linked = linkMentionInline(source, mention, target);
      // Only over the text we linked: anything typed since wins.
      if (linked != source &&
          await workspace.mutateNote(
            path,
            (current) => current == source ? linked : current,
          ) &&
          workspace.source == linked) {
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
    await _refreshEnrichment(userAction: true);
    unawaited(workspace.refreshIndex(always: true));
  }

  Future<void> _rejectEnrich(EnrichMention mention, NoteRef target) async {
    await _recordEnrichFeedback(mention, target.id, accepted: false);
    await _refreshEnrichment(userAction: true);
  }

  Future<void> _rejectEnrichTag(String tag) async {
    await _recordEnrichFeedback(
      EnrichMention(surface: tag, type: 'topic', line: 0),
      enrichTagEntity(tag),
      accepted: false,
    );
    await _refreshEnrichment(userAction: true);
  }

  Future<void> _createFromEnrich(EnrichMention mention) async {
    final created = await _createEntity(
      initialName: mention.surface,
      initialKind: mention.type,
    );
    if (created != null) await _acceptEnrich(mention, created);
  }
}
