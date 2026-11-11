part of '../app_mobile.dart';

extension _NavigationFlow on _HomeScreenState {
  Future<void> _tapProtected(String id) => _handleAtomSource(
    richController.protectedSource(id),
    allowEdit: true,
    protectedId: id,
  );

  Future<void> _longPressProtected(String id) async {
    final source = richController.protectedSource(id);
    final match = RegExp(
      r'^#tylog\.ref-note\s*\(\s*"((?:\\.|[^"\\])*)"',
    ).firstMatch(source.trim());
    if (match == null) return;
    final target = match[1]!.replaceAllMapped(RegExp(r'\\(.)'), (m) => m[1]!);
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: false,
      builder: (context) => AppSheet(
        title: 'Reference actions',
        children: [
          for (final action in ['Rename', 'Edit Typst', 'Remove'])
            ListTile(
              minTileHeight: 48,
              title: Text(action),
              onTap: () => Navigator.pop(context, action),
            ),
        ],
      ),
    );
    if (!mounted || action == null) return;
    if (action == 'Edit Typst') {
      await _editProtectedBlock(id);
      return;
    }
    if (action == 'Remove') {
      richController.replaceProtected(id, '');
      return;
    }
    final resolution =
        workspace.linkResolver?.resolve(target) ?? _resolveLink(target);
    final path = resolution.path;
    if (path == null) {
      showSnack(context, 'Resolve this reference before renaming.');
      return;
    }
    final currentTitle =
        index?.notes.where((n) => n.path == path).firstOrNull?.title ?? target;
    var draftTitle = currentTitle;
    final title = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename note'),
        content: TextFormField(
          initialValue: currentTitle,
          onChanged: (value) => draftTitle = value,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Title'),
          onFieldSubmitted: (value) => Navigator.pop(context, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, draftTitle),
            child: const Text('Rename'),
          ),
        ],
      ),
    );
    if (!mounted || title == null) return;
    if (_currentSource() != workspace.source) workspace.edit(_currentSource());
    final result = await workspace.renameNote(path, title);
    if (mounted) showSnack(context, result.message);
  }

  Future<void> _handleAtomSource(
    String source, {
    required bool allowEdit,
    String? protectedId,
  }) async {
    source = source.trim();
    final audio = RegExp(
      r'^#tylog\.attachment\("((?:\\.|[^"])*)",\s*kind:\s*"audio"',
    ).firstMatch(source);
    if (audio != null) {
      await _openAttachment(
        unescapeTypstString(audio[1]!).replaceFirst(RegExp(r'^/+'), ''),
      );
      return;
    }
    final match = RegExp(
      r'^#tylog\.date-ref\("(\d{4})-(\d{2})-(\d{2})"',
    ).firstMatch(source);
    if (match != null) {
      await _openDay(
        DateTime(
          int.parse(match.group(1)!),
          int.parse(match.group(2)!),
          int.parse(match.group(3)!),
        ),
      );
      return;
    }
    final link = RegExp(
      r'^#link\("(mailto:[^"]+|https?://[^"]+)"\)',
    ).firstMatch(source);
    if (link != null) {
      final uri = Uri.tryParse(link.group(1)!);
      if (uri != null && await canLaunchUrl(uri)) {
        await launchUrl(uri);
      } else {
        if (!mounted) return;
        showSnack(context, "Couldn't open ${link.group(1)}");
      }
      return;
    }
    // Tapping a note reference (`@mention` / `[[link]]`) navigates to the
    // note; a dangling reference offers to create it (Logseq muscle memory),
    // an ambiguous one lets the user pick which owner to open.
    final ref = RegExp(
      r'^#tylog\.ref-note\("((?:\\.|[^"])*)"',
    ).firstMatch(source);
    if (ref != null) {
      final target = ref
          .group(1)!
          .replaceAll(r'\"', '"')
          .replaceAll(r'\\', r'\');
      final heading = refNoteHeading(source);
      final resolution =
          workspace.linkResolver?.resolve(target) ?? _resolveLink(target);
      switch (resolution.status) {
        case LinkResolutionStatus.resolved:
          await _openNote(resolution.path!, heading: heading);
        case LinkResolutionStatus.ambiguous:
          await _chooseLinkOwner(
            target,
            resolution.candidates,
            heading: heading,
          );
        case LinkResolutionStatus.unresolved:
          final recent = workspace.recentNotePaths[target];
          if (recent != null) {
            await _openNote(recent, heading: heading);
          } else {
            final label = RegExp(
              r'\)\[([^\[\]]+)\]$',
            ).firstMatch(source)?.group(1);
            await _createFromLink(target, heading: heading, label: label);
          }
      }
      return;
    }
    if (allowEdit && protectedId != null) {
      await _editProtectedBlock(protectedId);
    }
  }

  Future<void> _createFromLink(
    String target, {
    String? heading,
    String? label,
  }) async {
    final generation = ++_openGeneration;
    final v = vault;
    if (v == null) return;
    // The resolver lags behind a just-created note until the background
    // rescan lands (minutes on a big vault), so check the direct
    // title->file mapping before claiming the note doesn't exist. Same
    // sanitization as Vault.page.
    final direct =
        'notes/${target.trim().replaceAll(RegExp(r'[\\/]'), '-')}.typ';
    if (await v.storage.exists(direct)) {
      await _openNote(direct, heading: heading, generation: generation);
      return;
    }
    if (!mounted) return;
    var name = (label?.trim().isNotEmpty == true ? label! : target).trim();
    var kind = 'note';
    final create = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Create note?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                initialValue: name,
                decoration: const InputDecoration(labelText: 'Name'),
                onChanged: (value) => name = value,
              ),
              DropdownButton<String>(
                value: kind,
                items: const [
                  DropdownMenuItem(value: 'note', child: Text('Note')),
                  DropdownMenuItem(value: 'person', child: Text('Person')),
                ],
                onChanged: (value) => setDialogState(() => kind = value!),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );
    if (create != true || !mounted || name.trim().isEmpty || vault != v) return;
    name = name.trim();
    final path = 'notes/${name.replaceAll(RegExp(r'[\\/]'), '-')}.typ';
    if (await v.storage.exists(path)) {
      if (mounted) showSnack(context, 'A page with that name already exists.');
      return;
    }
    final file = await workspace.createPage(name, kind: kind, id: target);
    // Open first — the refresh only serves future link resolution and can
    // block for minutes behind an in-flight full rebuild.
    await _openNote(file, heading: heading, generation: generation);
    if (heading == null && mounted) showSnack(context, 'Created $file');
    unawaited(workspace.refreshIndex(always: true));
  }

  Future<void> _chooseLinkOwner(
    String target,
    List<String> candidates, {
    String? heading,
  }) async {
    final generation = ++_openGeneration;
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: false,
      builder: (context) => AppSheet(
        title: '“$target” matches ${candidates.length} notes',
        children: [
          for (final path in candidates)
            ListTile(
              leading: const Icon(Icons.description_outlined),
              title: Text(path),
              onTap: () => Navigator.pop(context, path),
            ),
        ],
      ),
    );
    if (choice != null) {
      await _openNote(choice, heading: heading, generation: generation);
    }
  }

  Future<void> _editProtectedBlock(String id) async {
    final input = TextEditingController(
      text: richController.protectedSource(id),
    );
    final updated = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Typst block'),
        content: SizedBox(
          width: 640,
          child: TextField(
            controller: input,
            autofocus: true,
            minLines: 5,
            maxLines: 16,
            style: const TextStyle(fontFamily: 'monospace'),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, input.text),
            child: const Text('Apply'),
          ),
        ],
      ),
    );
    if (updated != null) richController.replaceProtected(id, updated);
  }

  Future<bool> _openNote(
    String path, {
    String? heading,
    int? generation,
    bool rememberView = true,
    String? searchQuery,
    int? searchOffset,
  }) async {
    final request = generation ??= ++_openGeneration;
    final external = workspace.externalEntities.where(
      (item) => item.id == path,
    );
    if (external.isNotEmpty) {
      if (dirty && !await _save()) return false;
      if (!mounted) return false;
      unawaited(
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (context) => ExternalEntityPage(
              entity: external.first,
              offlineSince: _oltMeta.failedAt == null
                  ? null
                  : (_oltMeta.lastSuccess ?? _oltMeta.failedAt),
              signedOut: _oltSignedOut,
              notes: index?.notes ?? const <NoteRef>[],
              onOpen: (path) {
                Navigator.of(context).pop();
                unawaited(_openPath(path));
              },
            ),
          ),
        ),
      );
      return true;
    }
    final v = vault;
    if (v == null) return false;
    if (dirty && !await _save()) return false;
    if (!mounted || request != _openGeneration || vault != v) return false;
    late final ({String source, int mutationVersion, int editRevision})
    snapshot;
    try {
      snapshot = await workspace.readNoteSnapshot(path);
    } on StateError {
      return false;
    } on FileSystemException {
      return false;
    }
    if (!mounted || request != _openGeneration || vault != v) return false;
    final openedNote = scanNote(path, snapshot.source);
    if (openedNote.kind == 'audio') {
      await _openAudioNote(openedNote, generation: request);
      return mounted && request == _openGeneration && vault == v;
    }
    final noteChanged = path != note;
    final fromToday =
        mode == 'normal' &&
        primaryDestination == 0 &&
        _backViews.isEmpty &&
        path != note;
    if (!workspace.adoptNoteRead(path, snapshot)) return false;
    if (rememberView &&
        (mode == 'library' || mode == 'journal' || mode == 'graph')) {
      _rememberView();
    } else if (rememberView && fromToday) {
      _rememberView(today: true);
    }
    _loadSource(snapshot.source);
    _searchRevealQuery = searchQuery;
    _searchRevealOffset = searchOffset;
    if (searchQuery != null) _searchRevealGeneration++;
    _rebuild(() {
      mode = 'normal';
      if (noteChanged) _editScreenshot = false;
    });
    if (heading != null) {
      final text = richController.text;
      final exact = RegExp(
        '^${RegExp.escape(heading)}\$',
        multiLine: true,
      ).firstMatch(text);
      final offset = exact?.start ?? text.indexOf(heading);
      if (offset >= 0) {
        richController.selection = TextSelection.collapsed(offset: offset);
      } else {
        if (mounted) showSnack(context, 'Heading "$heading" not found');
      }
    }
    final entry = _activeRegistryEntry;
    if (entry != null) {
      // Adopt another device's position on the first local open of a note
      // this device has never read (recordOpen keeps a local record if any).
      var synced = 0.0;
      for (final r in workspace.mergedReading) {
        if (r.path == path) {
          synced = r.progress;
          break;
        }
      }
      unawaited(
        vaultRegistry!
            .recordOpen(entry, path, fallbackProgress: synced)
            .then((_) => _writeReadingFile()),
      );
    }
    return true;
  }

  Future<bool> _openToday() async {
    final generation = ++_openGeneration;
    final v = vault;
    if (v == null) return false;
    if (dirty && !await _save()) return false;
    if (!mounted || generation != _openGeneration || vault != v) return false;
    final path = await workspace.ensureTodayNote();
    if (!mounted || generation != _openGeneration || vault != v) return false;
    if (!await _openNote(path, generation: generation, rememberView: false)) {
      return false;
    }
    _todayNotePath = path;
    _todayOpenedAt = DateTime.now();
    return true;
  }

  Future<bool> _captureTimestamp() async {
    if (vault == null) return false;
    _navDebounce?.cancel();
    _navDay = null;
    try {
      final path = await workspace.ensureTodayNote();
      if (!mounted) return false;
      if (note != path && !await _openToday()) return false;
      if (!mounted || note != path) return false;
      _timestampCapturePath = path;
      _backViews.clear();
      _showEditor();
      richController.appendTimestamp(DateTime.now());
      _rebuild(() => primaryDestination = 0);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || note != path) return;
        _captureFocus.requestFocus();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || note != path) return;
          final context = _captureFocus.context;
          final editable = context
              ?.findAncestorStateOfType<EditableTextState>()
              ?.renderEditable;
          final scroll = context
              ?.findAncestorWidgetOfExactType<TextField>()
              ?.scrollController;
          if (editable == null || scroll == null || !scroll.hasClients) return;
          final caret = editable.getLocalRectForCaret(
            richController.selection.extent,
          );
          scroll.jumpTo(
            (scroll.offset + caret.top - editable.size.height / 2).clamp(
              0.0,
              scroll.position.maxScrollExtent,
            ),
          );
        });
        WidgetsBinding.instance.ensureVisualUpdate();
      });
      return true;
    } catch (error) {
      if (mounted) showSnack(context, 'Could not capture: $error');
      return false;
    }
  }

  Future<bool> _openDay(DateTime day) async {
    final generation = ++_openGeneration;
    final v = vault;
    if (v == null) return false;
    if (dirty && !await _save()) return false;
    return _openNote(
      await workspace.ensureTodayNote(day),
      generation: generation,
    );
  }

  /// Steps the journal by [delta] days.
  ///
  /// Coalesced, because one step is not cheap: opening a day saves the dirty
  /// buffer, creates the month directory, checks for the file, writes it when
  /// missing and reads it back — five SAF round-trips that queue behind any
  /// running sync. Uncoalesced, a user who taps `>` four times waited for four
  /// of those sequences *and* left an empty daily note behind for every day
  /// merely passed through. Now the label moves on the tap, the taps collapse,
  /// and only the day actually landed on is created.
  void _stepDay(int delta, {DateTime? target}) {
    final from = _navDay ?? _dailyDateOf(note);
    if (from == null) return;
    final next = target ?? DateTime(from.year, from.month, from.day + delta);
    _rebuild(() => _navDay = next);
    _navDebounce?.cancel();
    _navDebounce = Timer(const Duration(milliseconds: 180), () {
      final target = _navDay;
      if (target == null || !mounted) return;
      unawaited(
        _openDay(target).whenComplete(() {
          if (!mounted) return;
          // Only clear when nothing has stepped past this open in the meantime.
          if (_navDay == target) _rebuild(() => _navDay = null);
        }),
      );
    });
  }

  /// Date of the currently open note when it is a daily journal file.
  DateTime? _dailyDateOf(String? path) {
    if (path == null) return null;
    final match = RegExp(
      r'^daily/\d{4}/\d{2}/(\d{4})-(\d{2})-(\d{2})\.typ$',
    ).firstMatch(path);
    if (match == null) return null;
    return DateTime(
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
    );
  }

  /// Swiping the date in the app bar steps the journal a day (left = next).
  /// By distance, not velocity: a slow drag has none worth reading.
  Widget _swipeDay(Widget child) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onHorizontalDragStart: (_) => _swipeDx = 0,
    onHorizontalDragUpdate: (details) => _swipeDx += details.delta.dx,
    onHorizontalDragEnd: (_) {
      if (_swipeDx.abs() >= 48) _stepDay(_swipeDx < 0 ? 1 : -1);
      _swipeDx = 0;
    },
    child: child,
  );

  Future<void> _showCalendarPicker() async {
    final open = _navDay ?? _dailyDateOf(vault == null ? null : note);
    final day = await showDialog<DateTime>(
      context: context,
      builder: (context) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Padding(
            padding: const EdgeInsets.all(kSpace12),
            child: MonthCalendar(
              screenshotDays: {
                for (final n in index?.notes ?? const <NoteRef>[])
                  if (n.kind == 'screenshot' && n.date != null) n.date!,
              },
              dayMarks: workspace.calendarDayMarks,
              initialMonth: open,
              currentDay: open,
              onOpenDay: (day) => Navigator.pop(context, day),
            ),
          ),
        ),
      ),
    );
    if (day != null) await _openDay(day);
  }

  Future<void> _openLink(String title) async {
    final generation = ++_openGeneration;
    final v = vault;
    if (v == null) return;
    final event = workspace.feedEvents
        .where((e) => e.id == title || e.title == title)
        .firstOrNull;
    if (event != null) {
      await workspace.materializeEvent(event.path);
      await _openNote(event.path, generation: generation);
      return;
    }
    final existing = _pathForLink(title);
    if (existing != null) {
      await _openNote(existing, generation: generation);
      return;
    }
    final file = await workspace.createPage(title);
    await _openNote(file, generation: generation);
    if (mounted) showSnack(context, 'Created $file');
    // Without the refresh the new note stays unresolvable to every chip
    // until the next unrelated scan; run it behind the navigation.
    unawaited(workspace.refreshIndex(always: true));
  }

  Future<void> _newPage({String kind = 'note'}) async {
    if (_newPageInFlight) return;
    _newPageInFlight = true;
    final generation = ++_openGeneration;
    try {
      final v = vault;
      if (v == null) return;
      final title = await _askPageTitle();
      if (!mounted || generation != _openGeneration || vault != v) return;
      if (title == null || title.trim().isEmpty) return;
      final template = await _chooseTemplate(v);
      if (!mounted || generation != _openGeneration || vault != v) return;
      if (dirty && !await _save()) return;
      if (!mounted || generation != _openGeneration || vault != v) return;
      final file = await workspace.createPage(
        title,
        kind: kind,
        template: template,
      );
      if (!await _openNote(file, generation: generation)) return;
      unawaited(workspace.refreshIndex(always: true));
      if (mounted) showSnack(context, 'Created $file');
    } catch (error) {
      if (mounted) showSnack(context, 'Could not create page: $error');
    } finally {
      _newPageInFlight = false;
    }
  }

  Future<String?> _chooseTemplate(Vault v) async {
    final templates =
        (await v.storage.list(path: '_system/templates'))
            .where(
              (entity) => !entity.isDirectory && entity.path.endsWith('.typ'),
            )
            .map((entity) => entity.path)
            .toList()
          ..sort();
    if (templates.isEmpty) return null;
    if (!mounted) return null;
    return showDialog<String?>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Choose template'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context),
            child: const Text('Blank note'),
          ),
          for (final file in templates)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, file),
              child: Text(file.split('/').last),
            ),
        ],
      ),
    );
  }

  Future<String?> _askPageTitle() {
    final title = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New page'),
        content: _dialogField(
          title,
          label: 'Title',
          autofocus: true,
          onSubmitted: (value) => Navigator.pop(context, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, title.text),
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  Future<void> _editCurrentMetadata() async {
    final v = vault;
    final ix = index;
    final n = note;
    if (v == null || ix == null || n == null) return;
    final path = n;
    final current = ix.notesByPath[path];
    if (current == null) return;
    if (current.metadataSource != 'typst-query') {
      final convert = await showConfirmDialog(
        context,
        title: 'Convert metadata header?',
        message:
            'This legacy or dynamic header could not be verified by Typst. Saving will replace only the metadata call with a canonical literal header; the note body is preserved.',
        confirmLabel: 'Convert',
      );
      if (!convert) return;
      if (!mounted) return;
    }
    final title = TextEditingController(text: current.title);
    final kindField = TextEditingController(text: current.kind);
    final details = TextEditingController(
      text: metadataLines(current, ix.notes),
    );
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit details'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SelectableText('ID: ${current.id}'),
              const SizedBox(height: kSpace12),
              _dialogField(title, label: 'Title'),
              const SizedBox(height: kSpace12),
              _dialogField(
                kindField,
                label: 'Kind',
                hint: 'note, project, person, place…',
              ),
              TextField(
                key: const Key('metadata-details'),
                controller: details,
                minLines: 4,
                maxLines: 12,
                decoration: const InputDecoration(
                  labelText: 'Details',
                  helperText:
                      'One per line, key:: value. alias::, tags:: and '
                      'part of:: take comma lists.',
                  helperMaxLines: 2,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (saved == true) {
      final kind = kindField.text.trim();
      final updated = replaceNoteHeader(
        _currentSource(),
        applyMetadataLines(
          current,
          details.text,
          ix.notes,
          title: title.text.trim().isEmpty ? null : title.text.trim(),
          kind: kind.isEmpty ? null : kind,
        ),
      );
      _loadSource(updated);
      _queueAutosave();
      await _save();
    }
  }
}
