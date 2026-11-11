part of '../app_mobile.dart';

extension _MagicFlow on _HomeScreenState {
  Future<String?> _askText(String title, {String? initialValue}) async {
    final input = TextEditingController(text: initialValue);
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: _dialogField(
          input,
          label: title,
          autofocus: true,
          onSubmitted: (value) => Navigator.pop(context, value),
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
    return value?.trim();
  }

  String _selectedText() {
    if (mode == 'normal') return richController.selectedPlainText;
    final editor = sourceController;
    final selection = editor.selection;
    if (!selection.isValid || selection.isCollapsed) return '';
    return editor.text.substring(selection.start, selection.end);
  }

  void _applyMagic(MagicRequest request) {
    if (mode == 'normal') {
      richController.applyMagic(request);
      return;
    }
    final editor = sourceController;
    final edit = applyMagicEdit(editor.text, editor.selection, request);
    editor.value = TextEditingValue(text: edit.text, selection: edit.selection);
    _queueAutosave();
  }

  Future<NoteRef?> _chooseNote({
    String? kind,
    bool create = false,
    String? heading,
  }) async {
    final notes =
        await _pagedPickerNotes(kind: kind) ??
        (index?.notes ?? const <NoteRef>[])
            .where((note) => kind == null || note.kind == kind)
            .toList();
    if (!mounted) return null;
    final chosen = await showModalBottomSheet<Object>(
      context: context,
      showDragHandle: false,
      builder: (context) => NotePickerSheet(
        notes: notes,
        heading: heading,
        createLabel: create ? 'Create ${kind ?? 'note'}' : null,
      ),
    );
    if (chosen is NoteRef) return chosen;
    if (chosen != NotePickerSheet.createSentinel) return null;
    final title = await _askText(
      'New ${kind ?? 'note'}',
      initialValue: _selectedText(),
    );
    if (title == null || title.isEmpty || vault == null) return null;
    final file = await workspace.createPage(title, kind: kind ?? 'note');
    unawaited(workspace.refreshIndex(always: true));
    return scanNote(file, await workspace.readNote(file));
  }

  List<NoteRef> get _entities =>
      (index?.notes ?? const <NoteRef>[])
          .where((item) => !structuralNoteKinds.contains(item.kind))
          .toList()
        ..sort((a, b) => a.title.compareTo(b.title));

  Future<NoteRef?> _chooseEntity() async {
    final paged = await _pagedPickerNotes();
    if (!mounted) return null;
    final chosen = await showModalBottomSheet<Object>(
      context: context,
      showDragHandle: false,
      builder: (context) => NotePickerSheet(
        notes: [
          ...?paged?.where((item) => !structuralNoteKinds.contains(item.kind)),
          if (paged == null) ..._entities,
          if (paged != null)
            ...workspace.externalEntities.map((e) => e.toNoteRef()),
        ],
        createLabel: 'New entity',
        subtitleFor: (note) =>
            note.path.startsWith('olt:') ? 'OpenLabTwin' : note.kind,
      ),
    );
    if (chosen is NoteRef) return chosen;
    return chosen == NotePickerSheet.createSentinel ? _createEntity() : null;
  }

  /// Reads picker candidates in bounded pages when the SQLite projection is
  /// complete. An incomplete projection falls back to the live index so a
  /// background scan never makes a picker appear empty.
  /// The move-to-app-storage backup, or null once the user deleted it (the
  /// sync screen kept showing a folder that no longer existed).
  Future<String?> _existingBackup(String? location) async {
    if (location == null) return null;
    try {
      final exists = location.startsWith('content://')
          ? (await AndroidTreeVaultStorage(
              uri: location,
              name: '',
            ).list()).isNotEmpty
          : await Directory(location).exists();
      return exists ? friendlyVaultPath(location) : null;
    } catch (_) {
      return null;
    }
  }

  Future<List<NoteRef>?> _pagedPickerNotes({String? kind}) async {
    final activeEntry = workspace.entry;
    if (activeEntry == null) return null;
    try {
      final db = await _databaseForVault(activeEntry);
      if (db == null || !await db.nodeProjectionComplete()) return null;
      final notes = <NoteRef>[];
      String? cursor;
      do {
        final page = await db.pageNodeSummaries(afterId: cursor, type: kind);
        for (final summary in page.nodes) {
          final attributes = jsonDecode(summary.attributesJson);
          if (attributes is! Map) continue;
          final json = attributes.cast<String, Object?>()
            ..['id'] = summary.id
            ..['title'] = summary.title
            ..['kind'] = summary.type;
          if (json['deletedAtMs'] != null || json['path'] is! String) {
            continue;
          }
          notes.add(NoteRef.fromJson(json));
        }
        cursor = page.nextCursor;
      } while (cursor != null);
      return notes;
    } catch (_) {
      return null;
    }
  }

  Future<NoteRef?> _createEntity({
    String? initialName,
    String? initialKind,
  }) async {
    final title = TextEditingController(text: initialName);
    final kindField = TextEditingController(text: initialKind);
    final aliases = TextEditingController();
    final fieldControllers = <String, TextEditingController>{};
    final selectedIcons = <String, String>{};
    var kindListenerAttached = false;
    final save = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          if (!kindListenerAttached) {
            kindListenerAttached = true;
            kindField.addListener(() => setDialogState(() {}));
          }
          final chosenKind = kindField.text.trim();
          final needsIcon =
              chosenKind.isNotEmpty &&
              !kindRegistry.value.containsKey(chosenKind);
          final selectedIcon =
              selectedIcons[chosenKind] ??
              kindIconPalette.entries
                  .where((entry) => entry.value == iconForKind(chosenKind))
                  .firstOrNull
                  ?.key ??
              'category';
          final fields = entityFieldsForKind(chosenKind, kindRegistry.value);
          for (final field in fields) {
            fieldControllers.putIfAbsent(field, TextEditingController.new);
          }
          return AlertDialog(
            title: const Text('New entity'),
            scrollable: true,
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _dialogField(title, label: 'Name', autofocus: true),
                const SizedBox(height: kSpace12),
                DropdownMenu<String>(
                  key: const ValueKey('entity-kind'),
                  expandedInsets: EdgeInsets.zero,
                  controller: kindField,
                  label: const Text('Kind'),
                  requestFocusOnTap: true,
                  enableFilter: true,
                  dropdownMenuEntries:
                      entityKindChoices([
                            ...kindRegistry.value.keys,
                            ...?index?.notes.map((n) => n.kind),
                          ])
                          .map(
                            (value) =>
                                DropdownMenuEntry(value: value, label: value),
                          )
                          .toList(),
                ),
                const SizedBox(height: kSpace12),
                if (needsIcon) ...[
                  const Text('Kind icon'),
                  KindIconPicker(
                    selected: selectedIcon,
                    onSelected: (icon) =>
                        setDialogState(() => selectedIcons[chosenKind] = icon),
                  ),
                  const SizedBox(height: kSpace12),
                ],
                _dialogField(aliases, label: 'Aliases, comma-separated'),
                const SizedBox(height: kSpace12),
                for (final field in fields)
                  KeyedSubtree(
                    key: ValueKey('entity-field-$field'),
                    child: Padding(
                      padding: EdgeInsets.only(
                        bottom: field == fields.last ? 0 : kSpace12,
                      ),
                      child: _dialogField(
                        fieldControllers[field]!,
                        label: entityFieldLabel(field),
                        keyboardType: field == 'email'
                            ? TextInputType.emailAddress
                            : field == 'link'
                            ? TextInputType.url
                            : null,
                      ),
                    ),
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
          );
        },
      ),
    );
    final name = title.text.trim();
    final entityKind = kindField.text.trim();
    final v = vault;
    if (save != true || name.isEmpty || entityKind.isEmpty || v == null) {
      return null;
    }
    if (!kindRegistry.value.containsKey(entityKind)) {
      try {
        await workspace.configureKind(
          entityKind,
          icon:
              selectedIcons[entityKind] ??
              kindIconPalette.entries
                  .where((entry) => entry.value == iconForKind(entityKind))
                  .firstOrNull
                  ?.key ??
              'category',
          label: labelForKind(entityKind) == 'Entity'
              ? entityKind
              : labelForKind(entityKind),
        );
      } catch (error) {
        if (mounted) showSnack(context, 'Could not save kind: $error');
        return null;
      }
      if (!identical(vault, v)) return null;
    }
    final file = await workspace.createPage(name);
    final source = await workspace.readNote(file);
    final created = scanNote(file, source);
    final updated = replaceNoteHeader(
      source,
      NoteMetadataDraft(
        id: created.id,
        title: created.title,
        kind: entityKind,
        tags: created.tags,
        aliases: _csvValues(aliases.text),
        properties: {
          ...created.properties,
          for (final field in entityFieldsForKind(
            entityKind,
            kindRegistry.value,
          ))
            if (fieldControllers[field]?.text.trim().isNotEmpty ?? false)
              field: fieldControllers[field]!.text.trim(),
        },
      ),
    );
    if (!await workspace.mutateNote(file, (_) => updated)) {
      return null;
    }
    unawaited(workspace.refreshIndex(always: true));
    return scanNote(file, updated);
  }

  void _updatePartOf(String parentId, {bool remove = false}) {
    final current = _currentNoteRef();
    if (current == null) return;
    final source = _currentSource();
    final fresh = scanNote(current.path, source);
    final value = fresh.properties['part_of'];
    final parents = <String>{
      if (value is String) value,
      if (value is List) ...value.whereType<String>(),
    };
    var updated = source;
    if (remove && fresh.project == parentId) {
      updated = replaceNoteFields(updated, const {'project': 'none'});
    }
    if (remove) {
      parents.remove(parentId);
    } else {
      parents.add(parentId);
    }
    if (remove && parents.isEmpty) {
      updated = removeNoteProperty(updated, 'part_of');
    } else {
      updated = replaceNotePartOf(
        updated,
        NoteMetadataDraft.fromNote(fresh),
        parents.toList(),
      );
    }
    _loadSource(updated);
    _queueAutosave();
    _rebuild(() {});
  }

  Future<void> _addParent() async {
    final path = note;
    final opened = vault;
    final parent = await _chooseEntity();
    if (!mounted ||
        parent == null ||
        note != path ||
        !identical(vault, opened)) {
      return;
    }
    _updatePartOf(parent.id);
  }

  Future<void> _runMagic(MagicAction action) async {
    switch (action) {
      case MagicAction.bold:
      case MagicAction.italic:
      case MagicAction.heading:
      case MagicAction.strike:
      case MagicAction.underline:
      case MagicAction.mono:
        _applyMagic(MagicRequest(action: action));
        return;
      case MagicAction.highlight:
        // The four highlight colours used to be reachable only by long-
        // pressing the toolbar button, which tooltips advertise but Android
        // has no way to discover. Surface them explicitly here instead.
        final chosen = await showModalBottomSheet<String>(
          context: context,
          showDragHandle: false,
          builder: (context) => AppSheet(
            title: 'Highlight',
            children: [
              for (final (fill, label) in kHighlightChoices)
                ListTile(
                  leading: Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: highlightSwatchColor(fill),
                      borderRadius: BorderRadius.circular(kRadiusSmall),
                      border: Border.all(
                        color: Theme.of(context).colorScheme.outlineVariant,
                      ),
                    ),
                  ),
                  title: Text(label),
                  onTap: () => Navigator.pop(context, fill),
                ),
            ],
          ),
        );
        if (!mounted) return;
        if (chosen == null) return;
        _applyMagic(MagicRequest(action: MagicAction.highlight, value: chosen));
        return;
      case MagicAction.equation:
        final selected = _selectedText();
        final value = selected.isEmpty ? await _askText('Equation') : selected;
        if (value == null || value.isEmpty) return;
        _applyMagic(MagicRequest(action: action, value: value));
        return;
      case MagicAction.table:
        final size = await _askTableSize();
        if (size == null) return;
        _applyMagic(
          MagicRequest(
            action: MagicAction.table,
            rows: size.$1,
            columns: size.$2,
          ),
        );
        return;
      case MagicAction.noteLink:
        final target = await _chooseNote(create: true);
        if (target != null) {
          _applyMagic(
            MagicRequest(action: action, id: target.id, value: target.title),
          );
        }
        return;
      case MagicAction.mention:
        final target = await _chooseEntity();
        if (target != null) {
          _applyMagic(
            MagicRequest(action: action, id: target.id, value: target.title),
          );
        }
        return;
      case MagicAction.project:
        await _addParent();
        return;
      case MagicAction.tag:
        final value = await _askText('Tag', initialValue: _selectedText());
        if (value != null && value.isNotEmpty) {
          _applyMagic(MagicRequest(action: action, value: value));
        }
        return;
      case MagicAction.task:
        final selected = _selectedText();
        if (selected.contains('\n')) {
          final lines = selected
              .split('\n')
              .map(
                (l) => l
                    .replaceFirst(RegExp(r'^(?:[•☐☑] |\d+\. |[-+] )'), '')
                    .trim(),
              )
              .where((l) => l.isNotEmpty)
              .toList();
          if (lines.length >= 2) {
            final reserved = <String>{};
            final tasks = <({String id, String text})>[];
            for (final line in lines) {
              final id = await vault!.nextTaskId(line, reserved: reserved);
              reserved.add(id);
              tasks.add((id: id, text: line));
            }
            if (mode == 'normal') {
              richController.insertTasks(tasks);
            } else {
              final snippets = tasks
                  .map((t) => taskSnippet(id: t.id, text: t.text))
                  .join('\n\n');
              final editor = sourceController;
              final selection = editor.selection;
              final start = selection.isValid
                  ? selection.start
                  : editor.text.length;
              final end = selection.isValid
                  ? selection.end
                  : editor.text.length;
              final before = editor.text.substring(0, start);
              final after = editor.text
                  .substring(end)
                  .replaceFirst(RegExp(r'^\n+'), '');
              final prefix = before.isEmpty
                  ? ''
                  : before.endsWith('\n\n')
                  ? ''
                  : before.endsWith('\n')
                  ? '\n'
                  : '\n\n';
              final inserted = '$prefix$snippets\n\n';
              editor.value = TextEditingValue(
                text: '$before$inserted$after',
                selection: TextSelection.collapsed(
                  offset: start + inserted.length,
                ),
              );
              _queueAutosave();
            }
            return;
          }
        }
        if (mode == 'normal') {
          await richController.createTaskLine();
        } else {
          final editor = sourceController;
          final caret = editor.selection.isValid
              ? editor.selection.extentOffset
              : editor.text.length;
          final start =
              editor.text.lastIndexOf(
                '\n',
                (caret - 1).clamp(0, editor.text.length),
              ) +
              1;
          final lineEnd = editor.text.indexOf('\n', caret);
          final end = lineEnd < 0 ? editor.text.length : lineEnd;
          final original = editor.text;
          final opened = vault!;
          final text = original.substring(start, end);
          final taskId = await vault!.nextTaskId(text);
          if (!mounted ||
              !identical(vault, opened) ||
              editor.text != original) {
            return;
          }
          final snippet = taskSnippet(id: taskId, text: text);
          editor.value = TextEditingValue(
            text: editor.text.replaceRange(start, end, snippet),
            selection: TextSelection.collapsed(offset: start + snippet.length),
          );
          _queueAutosave();
        }
        return;
      case MagicAction.time:
        _applyMagic(
          MagicRequest(action: action, value: localTime(DateTime.now())),
        );
        return;
      case MagicAction.date:
        final selected = _selectedText().replaceAll(RegExp(r'[^0-9-]'), '');
        final parsed = _parseMagicDate(selected);
        final date =
            parsed ??
            await showDatePicker(
              context: context,
              firstDate: DateTime(1900),
              lastDate: DateTime(2200),
              initialDate: DateTime.now(),
            );
        if (date != null) {
          _applyMagic(MagicRequest(action: action, value: isoDay(date)));
        }
        return;
      case MagicAction.citation:
        final key = await _chooseCitation();
        if (key != null) {
          _applyMagic(MagicRequest(action: action, value: key));
        }
        return;
      case MagicAction.attachment:
        await _insertAttachment();
        return;
      case MagicAction.audio:
        await _insertAudio();
        return;
      case MagicAction.report:
        await _createReport();
        return;
      case MagicAction.articles:
        await _saveLinksAsArticles();
        return;
    }
  }

  NoteRef? _currentNoteRef() {
    final v = vault;
    final file = note;
    if (v == null || file == null) return null;
    return index?.notesByPath[file];
  }

  DateTime? _parseMagicDate(String value) {
    if (RegExp(r'^\d{8}$').hasMatch(value)) {
      return DateTime(
        int.parse(value.substring(0, 4)),
        int.parse(value.substring(4, 6)),
        int.parse(value.substring(6, 8)),
      );
    }
    return DateTime.tryParse(value);
  }

  Future<(int, int)?> _askTableSize() async {
    final rows = TextEditingController(text: '2');
    final columns = TextEditingController(text: '2');
    String? error;
    final result = await showDialog<(int, int)>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Table size'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: _dialogField(
                      rows,
                      label: 'Rows',
                      autofocus: true,
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  const SizedBox(width: kSpace12),
                  Expanded(
                    child: _dialogField(
                      columns,
                      label: 'Columns',
                      keyboardType: TextInputType.number,
                    ),
                  ),
                ],
              ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: kSpace8),
                  child: Text(error!),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final rowCount = int.tryParse(rows.text);
                final columnCount = int.tryParse(columns.text);
                if (rowCount == null ||
                    columnCount == null ||
                    rowCount < 1 ||
                    rowCount > 10 ||
                    columnCount < 1 ||
                    columnCount > 10) {
                  setDialogState(() => error = 'Use 1–10');
                  return;
                }
                Navigator.pop(context, (rowCount, columnCount));
              },
              child: const Text('Insert'),
            ),
          ],
        ),
      ),
    );
    return result;
  }

  void _magicFeedback(String message) {
    if (!mounted) return;
    showSnack(context, message);
  }
}
