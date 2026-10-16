part of '../app_mobile.dart';

extension _AudioFlow on _HomeScreenState {
  Widget _audioShelf(List<NoteRef> notes) => AudioShelf(
    notes: notes,
    onOpen: (note) => unawaited(_openAudioNote(note)),
    onRecord: () => unawaited(_recordAudioNote()),
    onImport: () => unawaited(_importAudioNote()),
  );

  Future<void> _recordAudioNote({bool inline = false}) async {
    // Mid-recording parts save quietly; only the last one opens its note.
    Future<void> save(AudioTake take, {bool open = false}) => _createAudioNote(
      take.bytes,
      take.extension,
      peaks: take.peaks,
      durationMs: take.durationMs,
      inline: inline,
      at: take.startedAt,
      open: open,
    );
    final take = await showAudioRecorder(context, onPart: save);
    if (take == null || !mounted) return;
    await save(take, open: true);
  }

  /// Magic > Audio: record or import, then drop the player card into the open
  /// note (the day's page, say) instead of navigating away.
  Future<void> _insertAudio() async {
    final choice = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: false,
      builder: (context) => AppSheet(
        title: 'Audio',
        children: [
          ListTile(
            leading: const Icon(Icons.mic),
            title: const Text('Record'),
            onTap: () => Navigator.pop(context, true),
          ),
          ListTile(
            leading: const Icon(Icons.audio_file_outlined),
            title: const Text('Import file'),
            onTap: () => Navigator.pop(context, false),
          ),
        ],
      ),
    );
    if (choice == null || !mounted) return;
    await (choice
        ? _recordAudioNote(inline: true)
        : _importAudioNote(inline: true));
  }

  /// The player card for an audio attachment in a note body.
  Widget _audioCard(String assetPath, String label) {
    final v = vault!;
    NoteRef? audioNote;
    for (final n in index?.notes ?? const <NoteRef>[]) {
      if (n.kind == 'audio' &&
          n.attachments.any(
            (a) => a.path.replaceFirst(RegExp(r'^/+'), '') == assetPath,
          )) {
        audioNote = n;
        break;
      }
    }
    final pending = _pendingAudio[assetPath];
    final note = audioNote;
    return AudioInlineCard(
      key: ValueKey(assetPath),
      label: label,
      // Read from the file, not the index: the index is empty for minutes at
      // startup, and the chip must show its state at once.
      status: () async {
        final path =
            note?.path ?? 'notes/${audioAssetNote(assetPath).title}.typ';
        if (!await v.storage.existsNow(path)) {
          return (transcribed: false, translated: false, alias: null);
        }
        final text = utf8.decode(await v.storage.readBytesNow(path));
        final aliases = scanNote(path, text).aliases;
        return (
          transcribed: parseTranscript(text).isNotEmpty,
          translated: translationLangs(text).isNotEmpty,
          alias: aliases.isEmpty ? null : aliases.first,
        );
      },
      peaks: pending?.peaks ?? decodePeaks(note?.properties['peaks']),
      readPeaks: () => readPeakSidecar(assetPath, v.storage.readBytesNow),
      onPeaks: (peaks, ms) =>
          unawaited(writePeakSidecar(assetPath, peaks, v.storage.writeBytes)),
      readBytes: () async =>
          _pendingAudio[assetPath]?.bytes ??
          await v.storage.readBytesNow(assetPath),
      extension: assetPath.split('.').last,
      onExpand: (tab) => _openAudioAsset(assetPath, tab: tab),
    );
  }

  /// Tells the user a background save started and how it ended, and keeps
  /// the pending bytes servable until the copy lands.
  void _trackSave(String label, String path, Future<void> work) {
    if (mounted) showSnack(context, 'Saving $label…');
    _attachTasks[path] = work
        .then<void>(
          (_) {
            if (mounted) showSnack(context, 'Saved $label');
          },
          onError: (Object error) {
            if (mounted) showSnack(context, 'Could not save $label: $error');
          },
        )
        .whenComplete(() {
          _attachTasks.remove(path);
          _pendingAttach.remove(path);
          if (mounted) _refreshNoteAssets(_currentSource());
        });
  }

  /// A file shared from another app (voice recorder, call recording).
  Future<void> _saveSharedAudio(File source) =>
      _createAudioNote(null, source.path.split('.').last.toLowerCase(),
          source: source);

  Future<void> _importAudioNote({bool inline = false}) async {
    final picked = await FilePicker.pickFiles(type: FileType.audio);
    final source = picked?.files.single.path;
    if (source == null || !mounted) return;
    final extension = source.split('.').last.toLowerCase();
    if (!isAudioPath('.$extension')) {
      showSnack(context, 'Not an audio file: .$extension');
      return;
    }
    final bytes = await File(source).readAsBytes();
    await _createAudioNote(
      bytes,
      extension,
      peaks: extension == 'wav' ? (peaksFromWav(bytes) ?? const []) : const [],
      durationMs: audioDurationMs(bytes),
      inline: inline,
    );
  }

  /// One recording = file under assets/audio + a `kind: audio` note whose id,
  /// title and file name all carry the same timestamp stamp.
  Future<void> _createAudioNote(
    Uint8List? bytes,
    String extension, {
    File? source,
    List<int> peaks = const [],
    int? durationMs,
    bool inline = false,
    DateTime? at,
    bool open = true,
  }) async {
    final v = vault;
    if (v == null) return;
    final now = at ?? DateTime.now();
    final month = now.month.toString().padLeft(2, '0');
    String relative(String stamp) =>
        'assets/audio/${now.year}/$month/$stamp.$extension';
    var stamp = audioStamp(now);
    // The inline path must not wait on SAF (an `exists` call queues behind
    // the index), so it avoids collisions from what this session has used.
    if (inline
        ? _pendingAudio.containsKey(relative(stamp)) ||
              _audioNoteTasks.containsKey(relative(stamp))
        : await v.storage.exists(relative(stamp))) {
      stamp = audioStamp(now, withMillis: true);
    }
    final asset = relative(stamp);
    final title = audioTitle(stamp);
    final id = 'audio-$stamp';
    Future<String> persist() async {
      // A shared file is copied from disk (natively on Android) so a long
      // call never sits in memory; duration and peaks are filled in on open.
      if (source != null) {
        await importPlatformFile(v.storage, asset, source);
      } else {
        await v.storage.writeBytes(asset, bytes!);
      }
      final path = await workspace.createPage(title, kind: 'audio', id: id);
      await workspace.mutateNote(path, (current) {
        final header = replaceNoteHeader(
          current,
          NoteMetadataDraft(
            id: id,
            title: title,
            kind: 'audio',
            properties: {
              'duration_ms': ?durationMs,
              if (peaks.isNotEmpty) 'peaks': encodePeaks(peaks),
            },
          ),
        );
        return header + audioNoteBody(asset, '$stamp.$extension');
      });
      // Not awaited: a full refresh can take minutes on a big vault, and the
      // note opens from its own source below.
      unawaited(workspace.refreshIndex(updateStatus: false, always: true));
      return path;
    }

    try {
      if (inline) {
        // Chip first: the user sees the take land at once, the slow writes
        // follow in the background.
        _pendingAudio[asset] = (bytes: bytes!, peaks: peaks);
        _applyMagic(
          MagicRequest(
            action: MagicAction.attachment,
            value: '/$asset',
            kind: 'audio',
          ),
        );
        _trackSave('recording', asset, persist());
        _audioNoteTasks[asset] = _attachTasks[asset]!.whenComplete(() {
          _pendingAudio.remove(asset);
          _audioNoteTasks.remove(asset);
        });
        return;
      }
      final path = await persist();
      if (!open || !mounted) return;
      final note =
          index?.notesByPath[path] ??
          scanNote(path, await workspace.readNote(path));
      if (mounted) await _openAudioNote(note);
    } catch (error) {
      if (mounted) showSnack(context, 'Could not save recording: $error');
    }
  }

  Future<void> _openAudioNote(
    NoteRef note, {
    AudioTab tab = AudioTab.comments,
  }) async {
    final v = vault;
    if (v == null) return;
    List<String> selectedLanguages = const [];
    try {
      selectedLanguages = (await readAudioPolicy(v.storage)).translateTo;
    } catch (_) {}
    if (!mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => AudioNoteScreen(
          note: note,
          initialTab: tab,
          selectedLanguages: selectedLanguages,
          transcriptLangs: (audio) => transcriptJobLangs(v.storage, audio),
          onChanged: () => unawaited(
            workspace.refreshIndex(updateStatus: false, always: true),
          ),
          readSource: v.storage.readText,
          readBytes: v.storage.readBytesNow,
          writeBytes: v.storage.writeBytes,
          mutate: workspace.mutateNote,
          transcriptStatus: (audio) => transcriptJobStatus(v.storage, audio),
          requestTranscript: (audio, note) =>
              enqueueTranscript(v.storage, audioPath: audio, notePath: note),
          transcriptLang: (audio) => transcriptJobLang(v.storage, audio),
          translationStatus: (audio, target) =>
              translationJobStatus(v.storage, audio, target),
          requestTranslation: (audio, note, target, source, sourceLangs) =>
              enqueueTranslation(
                v.storage,
                audioPath: audio,
                notePath: note,
                target: target,
                sourceLang: source,
                sourceLangs: sourceLangs,
              ),
        ),
      ),
    );
  }

  /// Opens the comment/waveform screen for any audio file in the vault, e.g.
  /// a lesson's mp3. The first open creates a `kind: audio` note for it with
  /// a deterministic id and path (two devices opening the same file converge
  /// on one note) and a link back to the note whose chip was tapped.
  Future<void> _openAudioAsset(
    String assetPath, {
    AudioTab tab = AudioTab.comments,
  }) async {
    final v = vault;
    if (v == null) return;
    showSnack(context, 'Opening audio…');
    await _audioNoteTasks[assetPath];
    for (final n in index?.notes ?? const <NoteRef>[]) {
      if (n.kind == 'audio' && n.attachments.any((a) => a.path == assetPath)) {
        await _openAudioNote(n, tab: tab);
        return;
      }
    }
    final (:id, :title) = audioAssetNote(assetPath);
    final base = assetPath
        .split('/')
        .last
        .replaceFirst(RegExp(r'\.[^.]+$'), '');
    final origin = workspace.note == null
        ? null
        : index?.notesByPath[workspace.note!];
    try {
      final existed = await v.storage.exists('notes/$title.typ');
      final path = await workspace.createPage(title, kind: 'audio', id: id);
      if (!existed) {
        await workspace.mutateNote(path, (current) {
          final header = replaceNoteHeader(
            current,
            NoteMetadataDraft(id: id, title: title, kind: 'audio'),
          );
          return header +
              audioNoteBody(
                assetPath,
                base,
                fromId: origin != null && origin.kind != 'audio'
                    ? origin.id
                    : null,
                fromTitle: origin?.title,
              );
        });
        unawaited(workspace.refreshIndex(updateStatus: false, always: true));
      }
      if (!mounted) return;
      await _openAudioNote(
        tab: tab,
        NoteRef(
          id: id,
          path: path,
          title: title,
          kind: 'audio',
          outgoingLinks: const [],
        ),
      );
    } catch (error) {
      if (mounted) showSnack(context, 'Could not open audio: $error');
    }
  }
}
