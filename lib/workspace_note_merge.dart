part of 'workspace_controller.dart';

/// Stand-in for `/_system/tylog.typ` when checking that a moved body compiles:
/// every helper a body uses takes any arguments (`ref-note("x")[Label]`, tasks
/// with named fields). The old one-argument `ref-note(id)` rejected every page
/// with an ordinary labelled link.
const _mergeHelperStub =
    '#let _stub(..args) = [Reference]\n'
    '#let ref-note = _stub\n'
    '#let task = _stub\n'
    '#let attachment = _stub\n'
    '#let date-ref = _stub\n'
    '#let tag = _stub\n';

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
    final crossFolder =
        survivor.substring(0, survivor.lastIndexOf('/')) !=
        loser.substring(0, loser.lastIndexOf('/'));
    if (body == null && loserText.trim() != canonical.trim()) {
      throw StateError(
        'The page header could not be separated safely from its body.',
      );
    }
    if (crossFolder && body != null && body.trim().isNotEmpty) {
      TypstCompiler? compiler;
      try {
        compiler = await TypstCompiler.create();
      } catch (error) {
        // Native compilation is absent in the Flutter unit-test host.
        if (!error.toString().contains('Failed to load dynamic library')) {
          rethrow;
        }
        await _validateTypstBodyWithCli(body);
      }
      if (compiler != null) {
        try {
          final document = await compiler.compile(
            source: '#import "/_system/tylog.typ" as tylog\n$body',
            files: {
              '/_system/tylog.typ': Uint8List.fromList(
                utf8.encode(_mergeHelperStub),
              ),
            },
          );
          document.dispose();
        } catch (error) {
          throw StateError('The body is not valid standalone Typst: $error');
        } finally {
          compiler.dispose();
        }
      }
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
    final candidates = currentIndex.notes
        .where((n) => n.path != loser)
        .toList();
    for (var start = 0; start < candidates.length; start += 4) {
      final batch = candidates.skip(start).take(4).toList();
      final texts = await Future.wait<String>(
        batch.map<Future<String>>(
          (n) async => n.path == note ? source : readNote(n.path),
        ),
      );
      for (var i = 0; i < batch.length; i++) {
        final n = batch[i];
        final text = texts[i];
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
          if ((draft.date != null &&
                  metadata.date != null &&
                  draft.date != metadata.date) ||
              (draft.project != null &&
                  metadata.project != null &&
                  draft.project != metadata.project)) {
            throw StateError('The pages have conflicting dates or projects.');
          }
          final custom = Map.of(draft.properties)..remove('part_of');
          if (draft.kind != metadata.kind) {
            throw StateError('The pages have different kinds.');
          }
          if (custom.isNotEmpty) {
            if (!text.startsWith(
              replaceNoteHeader(
                '',
                NoteMetadataDraft.fromNote(scanNote(survivor, text)),
              ),
            )) {
              throw StateError(
                'Custom properties require a canonical survivor header.',
              );
            }
            for (final entry in custom.entries) {
              if (metadata.properties.containsKey(entry.key)) {
                if ((entry.value == null ||
                        entry.value is String ||
                        entry.value is num ||
                        entry.value is bool) &&
                    metadata.properties[entry.key].runtimeType ==
                        entry.value.runtimeType &&
                    metadata.properties[entry.key] == entry.value) {
                  continue;
                }
                throw StateError('Both pages have the property ${entry.key}.');
              }
              updated = replaceNoteProperty(updated, entry.key, entry.value);
            }
          }
          final aliases = {...metadata.aliases, remove.title, ...remove.aliases}
            ..remove(metadata.title);
          if (draft.tags.isNotEmpty &&
              !text.startsWith(
                replaceNoteHeader(
                  '',
                  NoteMetadataDraft.fromNote(scanNote(survivor, text)),
                ),
              )) {
            throw StateError(
              'Tagged pages require a canonical survivor header.',
            );
          }
          updated = replaceNoteFields(updated, {
            if (draft.date != null && metadata.date == null)
              'date': typstString(draft.date!),
            if (draft.project != null && metadata.project == null)
              'project': typstString(draft.project!),
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

Future<void> _validateTypstBodyWithCli(String body) async {
  final root = await Directory.systemTemp.createTemp('tylog-merge-check-');
  try {
    final helper = Directory('${root.path}/_system');
    await helper.create(recursive: true);
    await File(
      '${helper.path}/tylog.typ',
    ).writeAsString(_mergeHelperStub);
    final source = File('${root.path}/body.typ');
    await source.writeAsString('#import "/_system/tylog.typ" as tylog\n$body');
    final result = await Process.run('typst', [
      'compile',
      '--root',
      root.path,
      source.path,
      '${root.path}/body.pdf',
    ]);
    if (result.exitCode != 0) {
      throw StateError(
        'The body is not valid standalone Typst: ${result.stderr}',
      );
    }
  } finally {
    await root.delete(recursive: true);
  }
}
