part of 'workspace_controller.dart';

enum RenameNoteFailure { invalidTitle, collision, unavailable, writeFailed }

class RenameNoteResult {
  const RenameNoteResult.success(this.path)
    : failure = null,
      message = 'Renamed';
  const RenameNoteResult.failure(this.failure, this.message) : path = null;

  final String? path;
  final RenameNoteFailure? failure;
  final String message;
  bool get succeeded => failure == null;
}

extension _NoteRename on WorkspaceController {
  Future<RenameNoteResult> _renameNote(String path, String newTitle) async {
    final title = newTitle.trim();
    if (title.isEmpty ||
        title.contains(RegExp(r'[\\/]')) ||
        title.codeUnits.any((c) => c < 32 || c == 127)) {
      return const RenameNoteResult.failure(
        RenameNoteFailure.invalidTitle,
        'Use a non-empty title without / or \\.',
      );
    }
    final opened = vault;
    final generation = _vaultGeneration;
    final currentIndex = index;
    if (opened == null || currentIndex == null) {
      return const RenameNoteResult.failure(
        RenameNoteFailure.unavailable,
        'The note index is not ready.',
      );
    }
    final safe = title.replaceAll(RegExp(r'[\\/]'), '-');
    final newPath = '${path.substring(0, path.lastIndexOf('/') + 1)}$safe.typ';
    final resolver = linkResolver ?? LinkResolver(currentIndex.notes);
    final referrers = <String>{
      ...currentIndex.backlinksByTarget[path] ?? const <String>[],
    };
    final targets = <String>{};
    final oldNote = currentIndex.notes.where((n) => n.path == path).firstOrNull;
    if (oldNote == null) {
      return const RenameNoteResult.failure(
        RenameNoteFailure.unavailable,
        'The note is no longer available.',
      );
    }
    for (final target in {
      oldNote.title,
      path.split('/').last.replaceFirst(RegExp(r'\.typ$'), ''),
      ...oldNote.aliases,
    }) {
      if (resolver.resolve(target).path == path) {
        targets.add(target);
      }
    }
    // The editor buffer can contain references absent from the disk index.
    if (note case final openPath?) referrers.add(openPath);
    referrers.remove(path);
    var result = const RenameNoteResult.failure(
      RenameNoteFailure.unavailable,
      'The vault changed.',
    );
    try {
      await _queueNoteMutation(path, () async {
        if (!_owns(opened, generation)) return false;
        if (currentIndex.notes.any((n) => n.path != path && n.title == title) ||
            (newPath != path && await opened.storage.exists(newPath))) {
          result = const RenameNoteResult.failure(
            RenameNoteFailure.collision,
            'A note with that title or file already exists.',
          );
          return false;
        }
        if (!_owns(opened, generation)) return false;
        String current;
        String updated;
        do {
          current = note == path ? source : await opened.readText(path);
          if (!_owns(opened, generation)) return false;
          final metadata = scanNote(path, current);
          updated = replaceNoteHeader(
            current,
            NoteMetadataDraft(
              id: metadata.id,
              title: title,
              kind: metadata.kind,
              project: metadata.project,
              date: metadata.date,
              tags: metadata.tags,
              aliases: metadata.aliases,
              properties: metadata.properties,
            ),
          );
          // Preserve edits typed while the durable write was in flight.
          await _persistNote(opened, newPath, updated);
          if (!_owns(opened, generation)) return false;
        } while (note == path && source != current);
        if (note == path) {
          note = newPath;
          source = updated;
          _setDirty(false);
          savedRevision = editRevision;
          _lastSavedPath = newPath;
          _lastSavedSource = updated;
        }
        if (newPath != path) {
          final marker = await opened.storage.markIndexDirty(path);
          await _persistNote(opened, path, null);
          await opened.storage.commitIndexWrite(marker, path);
          opened.restoreWriteMarkers(path, stale: true, pendingSync: true);
        }
        _noteMutationVersions[path] = (_noteMutationVersions[path] ?? 0) + 1;
        _noteMutationVersions[newPath] =
            (_noteMutationVersions[newPath] ?? 0) + 1;
        result = RenameNoteResult.success(newPath);
        notifyListeners();
        return true;
      });
      if (!result.succeeded) return result;
      for (final other in referrers) {
        if (!_owns(opened, generation)) {
          return const RenameNoteResult.failure(
            RenameNoteFailure.unavailable,
            'The vault changed.',
          );
        }
        if (!await mutateNote(
          other,
          (text) => _renameReferences(text, targets, oldNote.title, title),
        )) {
          throw StateError('Could not update references in $other');
        }
      }
      return result;
    } catch (error) {
      return RenameNoteResult.failure(
        RenameNoteFailure.writeFailed,
        'Rename could not finish: $error',
      );
    } finally {
      if (_owns(opened, generation) && result.succeeded) {
        unawaited(refreshIndex(always: true));
      }
    }
  }
}

String _renameReferences(
  String source,
  Set<String> targets,
  String oldTitle,
  String title,
) {
  final firstArgument = RegExp(
    r'^#tylog\.ref-note\s*\(\s*("((?:\\.|[^"\\])*)")',
  );
  for (final call in locateTypstCalls(
    source,
    names: const {'tylog.ref-note'},
  ).reversed) {
    final match = firstArgument.firstMatch(call.source);
    if (match == null) continue;
    final target = match[2]!.replaceAllMapped(RegExp(r'\\(.)'), (m) => m[1]!);
    if (!targets.contains(target)) continue;
    var replacement = call.source;
    // Only a plain label equal to the old title follows the rename.
    final content = RegExp(r'\)\s*\[([\s\S]*)\]$').firstMatch(replacement);
    if (content != null && unescapeMarkup(content[1]!) == oldTitle) {
      replacement = replacement.replaceRange(
        content.end - content[1]!.length - 1,
        content.end - 1,
        escapeMarkup(title),
      );
    }
    replacement = replacement.replaceRange(
      match.end - match[1]!.length,
      match.end,
      typstString(title),
    );
    source = source.replaceRange(call.start, call.end, replacement);
  }
  return source;
}
