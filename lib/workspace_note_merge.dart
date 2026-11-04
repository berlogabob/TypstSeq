part of 'workspace_controller.dart';

class DuplicateMergePreview {
  DuplicateMergePreview._(this.survivor, this.loser, this.before, this.after);
  final String survivor;
  final String loser;
  final Map<String, String> before;
  final Map<String, String> after;
  List<String> get files => before.keys.toList()..sort();
}

extension _DuplicateMerge on WorkspaceController {
  Future<DuplicateMergePreview> _previewDuplicateMerge(
    String survivor,
    String loser,
  ) async {
    final opened = vault;
    final currentIndex = index;
    if (opened == null ||
        currentIndex == null ||
        survivor == loser ||
        note == loser ||
        survivor.startsWith('ext/') ||
        loser.startsWith('ext/')) {
      throw StateError(
        'These pages cannot be merged. Close the page being removed first.',
      );
    }
    final keep = currentIndex.notes
        .where((n) => n.path == survivor)
        .firstOrNull;
    final remove = currentIndex.notes.where((n) => n.path == loser).firstOrNull;
    if (keep == null || remove == null) {
      throw StateError('Page no longer exists.');
    }
    final loserText = await readNote(loser);
    final draft = NoteMetadataDraft.fromNote(scanNote(loser, loserText));
    final canonical = replaceNoteHeader('', draft);
    final body = loserText.startsWith(canonical)
        ? loserText.substring(canonical.length)
        : null;
    if (draft.date != null ||
        draft.project != null ||
        draft.properties.keys.any((k) => k != 'part_of') ||
        (body == null && loserText.trim() != canonical.trim()) ||
        (body != null &&
            body.trim().isNotEmpty &&
            survivor.substring(0, survivor.lastIndexOf('/')) !=
                loser.substring(0, loser.lastIndexOf('/')) &&
            !RegExp(
              r"^[\p{L}\p{N}\s.,!?;:'’()\-]*$",
              unicode: true,
            ).hasMatch(body))) {
      throw StateError(
        'Only canonical pages without date, project, or other properties can be merged; bodies moved between folders must be plain text.',
      );
    }
    final resolver = LinkResolver(currentIndex.notes);
    final targets = <String>{};
    for (final value in {
      remove.id,
      remove.title,
      ...remove.aliases,
      loser.split('/').last.replaceFirst(RegExp(r'\.typ$'), ''),
    }) {
      if (value.isNotEmpty && resolver.resolve(value).path == loser) {
        targets.add(value);
      }
    }
    if (!targets.contains(remove.id)) {
      throw StateError('The page ID is ambiguous.');
    }
    final before = <String, String>{loser: loserText};
    final after = <String, String>{};
    for (final n in currentIndex.notes) {
      if (n.path == loser) continue;
      final text = n.path == note ? source : await readNote(n.path);
      var updated = _renameReferences(
        text,
        targets,
        remove.title,
        keep.id,
        labelTitle: keep.title,
      );
      if (updated.contains(typstString(remove.id))) {
        throw StateError(
          'An unsupported reference to the page ID remains in ${n.path}.',
        );
      }
      if (n.path == survivor) {
        final metadata = scanNote(survivor, updated);
        final aliases = {...metadata.aliases, remove.title, ...remove.aliases}
          ..remove(metadata.title);
        if (draft.tags.isNotEmpty &&
            !text.startsWith(
              replaceNoteHeader(
                '',
                NoteMetadataDraft.fromNote(scanNote(survivor, text)),
              ),
            )) {
          throw StateError('Tagged pages require a canonical survivor header.');
        }
        updated = replaceNoteFields(updated, {
          if (draft.tags.isNotEmpty)
            'tags':
                '(${{...metadata.tags, ...draft.tags}.map(typstString).map((s) => '$s,').join(' ')})',
          'aliases':
              '(${aliases.map(typstString).map((s) => '$s,').join(' ')})',
        });
        updated = replaceNotePartOf(
          updated,
          NoteMetadataDraft.fromNote(metadata),
          {...metadata.partOf, ...remove.partOf}.toList(),
        );
        if (body != null && body.trim().isNotEmpty) {
          final mergedBody = _renameReferences(
            body,
            targets,
            remove.title,
            keep.id,
            labelTitle: keep.title,
          );
          if (mergedBody.contains(typstString(remove.id))) {
            throw StateError(
              'An unsupported reference to the page ID remains in $loser.',
            );
          }
          updated =
              '$updated\n\n== Merged from ${escapeMarkup(remove.title)}\n\n$mergedBody';
        }
      }
      if (updated != text) {
        if (n.path.startsWith('ext/')) {
          throw StateError('A reference is in a read-only mount.');
        }
        before[n.path] = text;
        after[n.path] = updated;
      }
    }
    before.putIfAbsent(
      survivor,
      () => throw StateError('Survivor could not be updated.'),
    );
    return DuplicateMergePreview._(survivor, loser, before, after);
  }

  Future<void> _mergeDuplicate(DuplicateMergePreview preview) async {
    final opened = vault;
    if (opened == null || note == preview.loser) {
      throw StateError('The vault or open page changed.');
    }
    for (final entry in preview.before.entries) {
      final current = entry.key == note ? source : await readNote(entry.key);
      if (current != entry.value) {
        throw StateError('A page changed; preview the merge again.');
      }
    }
    for (final entry in preview.after.entries) {
      if (!await mutateNote(entry.key, (current) {
        if (current != preview.before[entry.key]) {
          throw StateError('A page changed; preview the merge again.');
        }
        return entry.value;
      })) {
        throw StateError('Could not update ${entry.key}.');
      }
    }
    await opened.storage.createDirectory(decisionsDir);
    final device = deviceId ?? 'unknown';
    await opened.storage.appendBytes(
      '$decisionsDir/$device.jsonl',
      utf8.encode(
        encodeDecisions([
          Decision(
            at: DateTime.now().toIso8601String(),
            device: device,
            item: preview.loser,
            source: 'duplicate-merge',
            action: 'accepted',
            target: preview.survivor,
          ),
        ]),
      ),
    );
    final deleted = await _queueNoteMutation(preview.loser, () async {
      if (!identical(vault, opened) ||
          note == preview.loser ||
          await opened.readText(preview.loser) !=
              preview.before[preview.loser]) {
        throw StateError('The page changed; preview the merge again.');
      }
      await _persistNote(opened, preview.loser, null);
      opened.markLocallyWritten(preview.loser);
      return true;
    });
    if (!deleted) throw StateError('Could not delete ${preview.loser}.');
    await refreshIndex(always: true);
  }
}
