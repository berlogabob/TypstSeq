part of '../app_mobile.dart';

extension _IncomingFlow on _HomeScreenState {
  Future<void> _decideIncoming(NoteRef note, String action) async {
    final v = vault;
    final device = vaultRegistry?.deviceId;
    if (v == null || device == null) return;
    var targetDay = isoDay(DateTime.now());
    if (action == 'scheduled') {
      final selected = await showDatePicker(
        context: context,
        firstDate: DateTime(1900),
        lastDate: DateTime(2200),
        initialDate: DateTime.now(),
      );
      if (selected == null || !mounted) return;
      targetDay = isoDay(selected);
    }
    final external = note.path.startsWith('olt:');
    if (action == 'added-to-today' || action == 'scheduled') {
      final day = action == 'added-to-today'
          ? DateTime.now()
          : DateTime.parse(targetDay);
      final path = await workspace.ensureTodayNote(day);
      await workspace.mutateNote(path, (source) {
        final line =
            '- #tylog.ref-note(${typstString(note.id)})[${escapeMarkup(note.title)}]';
        if (source.contains('ref-note(${typstString(note.id)})')) return source;
        return appendAboveAutoBlock(source, line);
      });
    }
    if (external && (action == 'added-to-today' || action == 'scheduled')) {
      final props = <String, Object?>{
        'source': 'openlabtwin',
        'derivation': 'institutional',
        'attention': 'acted',
        if (note.properties['starts_at'] != null)
          'starts_at': note.properties['starts_at'],
        if (note.properties['ends_at'] != null)
          'ends_at': note.properties['ends_at'],
      };
      final path = await workspace.createPage(
        note.title,
        kind: note.kind,
        id: note.id,
      );
      await workspace.mutateNote(
        path,
        (source) => replaceNoteHeader(
          source,
          NoteMetadataDraft(
            id: note.id,
            title: note.title,
            kind: note.kind,
            properties: props,
          ),
        ),
      );
    }
    if (external) {
      final dir = await oltCacheDirectory();
      await addDecidedOltId(dir, note.id);
      if (mounted) _markOltDecided(note.id);
      final row = Decision(
        at: DateTime.now().toIso8601String(),
        device: device,
        item: note.id,
        source: 'openlabtwin',
        action: action,
        target: action == 'scheduled' ? targetDay : null,
      );
      await _appendIncomingDecision(v, device, row);
      unawaited(workspace.refreshIndex(updateStatus: false, always: true));
      return;
    }
    final newAttention = action == 'dismissed' ? 'archived' : 'acted';
    await workspace.mutateNote(note.path, (source) {
      final current = NoteMetadataDraft.fromNote(scanNote(note.path, source));
      return replaceNoteHeader(
        source,
        NoteMetadataDraft(
          id: current.id,
          title: current.title,
          kind: current.kind,
          project: current.project,
          date: current.date,
          tags: current.tags,
          aliases: current.aliases,
          properties: {
            ...current.properties,
            'attention': newAttention,
            // The screenshot shelf reads its own status vocabulary.
            if (note.kind == 'screenshot') 'status': newAttention,
          },
        ),
      );
    });
    final row = Decision(
      at: DateTime.now().toIso8601String(),
      device: device,
      item: note.id,
      source: note.kind,
      action: action,
      target: action == 'scheduled' ? targetDay : null,
    );
    await _appendIncomingDecision(v, device, row);
    unawaited(workspace.refreshIndex(updateStatus: false, always: true));
  }

  Future<void> _appendIncomingDecision(Vault v, String device, Decision row) =>
      _enrichLedgerWrite = _enrichLedgerWrite.then((_) async {
        final ledger = '$decisionsDir/$device.jsonl';
        await v.storage.createDirectory(decisionsDir);
        final existing = await v.storage.exists(ledger)
            ? await v.storage.readText(ledger)
            : '';
        await v.storage.writeText(ledger, '$existing${encodeDecisions([row])}');
      });
}
