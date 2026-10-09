part of '../rich_editor.dart';

class TyLogRichEditor extends StatefulWidget {
  const TyLogRichEditor({
    super.key,
    required this.controller,
    this.focusNode,
    required this.onInsert,
    this.onMentionQuery,
    this.onCommandSelected,
    this.onCreateNote,
    this.onSelectMention,
    this.popupBottomY,
  });

  final double? Function()? popupBottomY;
  final TyLogEditingController controller;
  final FocusNode? focusNode;
  final Future<void> Function() onInsert;

  /// Resolves candidates for the inline "@" mention popup. Kept decoupled
  /// from tylog_core's search index — the parent maps its own search
  /// results into [MentionSuggestion]s.
  final Future<List<MentionSuggestion>> Function(
    String query,
    AutocompleteTriggerKind kind,
  )?
  onMentionQuery;

  /// Actions offered by the inline "/" command palette. Defaults to the
  /// same action set as the Magic bottom-sheet menu, in the same order.

  /// Invoked when a "/" palette entry is selected — the parent should run
  /// the exact same handler the Magic menu uses for that action.
  final Future<void> Function(MagicAction action)? onCommandSelected;

  /// Materialises the page a "create" mention row names, Logseq-style: Enter
  /// on `[[New Page` creates the note immediately and returns its id, so the
  /// inserted reference resolves instead of dangling until someone taps the
  /// chip and confirms a dialog. Returning null falls back to the old
  /// unresolved-chip behavior.
  final Future<String?> Function(String title)? onCreateNote;
  final Future<void> Function(MentionSuggestion)? onSelectMention;

  @override
  State<TyLogRichEditor> createState() => _TyLogRichEditorState();
}

class TyLogReadView extends StatefulWidget {
  const TyLogReadView({
    super.key,
    required this.source,
    this.imageResolver,
    this.resolveKind,
    this.onAtomTap,
    this.taskBuilder,
  });

  final Widget Function(String source)? taskBuilder;
  final String source;
  final Future<Uint8List?> Function(String path)? imageResolver;
  final String? Function(String target)? resolveKind;
  final void Function(String source)? onAtomTap;

  @override
  State<TyLogReadView> createState() => _TyLogReadViewState();
}

class _TyLogReadViewState extends State<TyLogReadView> {
  late final TyLogEditingController controller = TyLogEditingController(
    source: widget.source,
    onSourceChanged: (_) {},
    onError: (_) {},
    onProtectedTap: (id) =>
        widget.onAtomTap?.call(controller.protectedSource(id)),
    imageResolver: widget.imageResolver,
    resolveKind: widget.resolveKind,
  );

  @override
  void didUpdateWidget(TyLogReadView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.source != oldWidget.source) controller.loadSource(widget.source);
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  // Text.rich (RenderParagraph), not SelectableText.rich (RenderEditable):
  // RenderEditable mispositions WidgetSpans whose size changes after first
  // layout (async inline images), painting chips over the surrounding text.
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      controller.imageContentWidth = constraints.maxWidth;
      return SelectionArea(
        child: Text.rich(
          controller.readTextSpan(
            context,
            style: Theme.of(
              context,
            ).textTheme.bodyLarge?.copyWith(height: 1.55),
            tappable: widget.onAtomTap != null,
            taskBuilder: widget.taskBuilder,
          ),
        ),
      );
    },
  );
}

const _defaultAutocompleteDebounce = Duration(milliseconds: 150);
const _autocompleteRowHeight = 48.0;
const _autocompleteMaxVisible = 6;

class _TyLogRichEditorState extends State<TyLogRichEditor> {
  late final FocusNode focusNode;
  final GlobalKey _editorKey = GlobalKey();
  final ScrollController _taskScroll = ScrollController();
  final ValueNotifier<_AutocompleteState?> _autocomplete = ValueNotifier(null);
  OverlayEntry? _overlayEntry;
  Timer? _debounce;
  int _mentionQueryToken = 0;
  final GlobalKey _headingButtonKey = GlobalKey();
  final GlobalKey _highlightButtonKey = GlobalKey();
  TyLogWindowController? _window;
  final ScrollController _windowScroll = ScrollController();
  final GlobalKey _windowFieldKey = GlobalKey();
  int _renderedWindowStart = 0;
  String? _taskField;
  String? _taskFieldBlock;
  int _taskFieldOffset = 0;
  String? _taskFieldText;
  final TextEditingController _dateInput = TextEditingController();
  final FocusNode _dateFocus = FocusNode();
  List<DateTime> get _dateCandidates =>
      parseDateWords(_dateInput.text, DateTime.now());

  @override
  void initState() {
    super.initState();
    if (debugEnableEditorWindow) _attachWindow();
    focusNode = widget.focusNode ?? FocusNode();
    focusNode.onKeyEvent = _handleKey;
    _dateFocus.onKeyEvent = _handleKey;
    focusNode.addListener(_focusChanged);
    widget.controller.addListener(_handleControllerChanged);
  }

  void _focusChanged() {
    if (!focusNode.hasFocus && _taskField == null) _cancelAutocomplete();
    setState(() {});
  }

  bool _checkboxSelection() {
    final c = widget.controller;
    if (!c.selection.isValid) return false;
    final hit = c.document._blockAt(c.selection.start, preferPrevious: true);
    return hit != null &&
        c.document.blocks[hit.index].style == TyLogBlockStyle.taskLine &&
        c.selection.start < hit.start + 2;
  }

  KeyEventResult _handleKey(FocusNode _, KeyEvent event) {
    if (event is KeyDownEvent &&
        (event.logicalKey == LogicalKeyboardKey.enter ||
            event.logicalKey == LogicalKeyboardKey.numpadEnter) &&
        (HardwareKeyboard.instance.isControlPressed ||
            HardwareKeyboard.instance.isMetaPressed) &&
        _taskField == null &&
        widget.controller.currentTaskBlockId != null) {
      widget.controller.cycleTaskStatus();
      return KeyEventResult.handled;
    }
    if (event is KeyDownEvent && _autocomplete.value != null) {
      final key = event.logicalKey;
      if (key == LogicalKeyboardKey.arrowDown) {
        _moveHighlight(1);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowUp) {
        _moveHighlight(-1);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.enter ||
          key == LogicalKeyboardKey.numpadEnter) {
        _activateHighlighted();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.escape) {
        _cancelAutocomplete();
        focusNode.requestFocus();
        return KeyEventResult.handled;
      }
    }
    if (event is! KeyDownEvent || event.logicalKey != LogicalKeyboardKey.keyZ) {
      return KeyEventResult.ignored;
    }
    final keyboard = HardwareKeyboard.instance;
    if (!keyboard.isControlPressed && !keyboard.isMetaPressed) {
      return KeyEventResult.ignored;
    }
    keyboard.isShiftPressed
        ? widget.controller.redo()
        : widget.controller.undo();
    return KeyEventResult.handled;
  }

  void _handleControllerChanged() {
    if (_taskField != null) {
      final c = widget.controller;
      if ((c.selection.isValid &&
              (!c.selection.isCollapsed ||
                  c.currentTaskBlockId != _taskFieldBlock)) ||
          c.text != _taskFieldText) {
        _cancelAutocomplete();
      }
      return;
    }
    final selection = widget.controller.selection;
    if (!selection.isValid || !selection.isCollapsed) {
      _cancelAutocomplete();
      return;
    }
    final trigger = detectTrigger(widget.controller.text, selection.baseOffset);
    if (trigger == null) {
      _cancelAutocomplete();
      return;
    }
    if (_autocomplete.value?.trigger != trigger) _mentionQueryToken++;
    if (trigger.kind == AutocompleteTriggerKind.command) {
      _debounce?.cancel();
      _autocomplete.value = _AutocompleteState(
        trigger: trigger,
        mentionItems: const [],
        commandItems: _filterCommands(
          trigger.query,
        ).where((a) => a != MagicAction.task).toList(),
        taskItems:
            [
              for (final command
                  in widget.controller.currentTaskBlockId == null
                      ? const ['todo', 'task']
                      : taskCommands.where((c) => c != 'task'))
                if (command.startsWith(trigger.query.toLowerCase())) command,
            ]..sort(
              (a, b) => a == trigger.query
                  ? -1
                  : b == trigger.query
                  ? 1
                  : 0,
            ),
        highlighted: 0,
        loading: false,
      );
      _ensureOverlay();
      return;
    }
    final previous = _autocomplete.value;
    final samePosition =
        previous != null &&
        _isMentionLike(previous.trigger.kind) &&
        previous.trigger.start == trigger.start;
    _autocomplete.value = _AutocompleteState(
      trigger: trigger,
      mentionItems: samePosition ? previous.mentionItems : const [],
      commandItems: const [],
      highlighted: 0,
      loading: true,
    );
    _ensureOverlay();
    _debounce?.cancel();
    _debounce = Timer(
      _defaultAutocompleteDebounce,
      () => _runMentionQuery(trigger),
    );
  }

  List<MagicAction> _filterCommands(String query) {
    final actions = kMagicActionDisplay.keys.toList();
    if (query.isEmpty) return actions;
    return actions
        .where((action) => magicActionMatches(action, query))
        .toList();
  }

  Future<void> _runMentionQuery(AutocompleteTrigger trigger) async {
    final onMentionQuery = widget.onMentionQuery;
    if (onMentionQuery == null) return;
    final token = _mentionQueryToken;
    final results = await onMentionQuery(trigger.query, trigger.kind);
    if (!mounted || token != _mentionQueryToken) return;
    final current = _autocomplete.value;
    if (current == null ||
        !_isMentionLike(current.trigger.kind) ||
        current.trigger.start != trigger.start) {
      return;
    }
    _autocomplete.value = _AutocompleteState(
      trigger: current.trigger,
      mentionItems: orderMentionSuggestions(results),
      commandItems: const [],
      highlighted: 0,
      loading: false,
    );
  }

  void _moveHighlight(int delta) {
    final state = _autocomplete.value;
    if (state == null) return;
    final count = _isMentionLike(state.trigger.kind)
        ? state.mentionItems.length
        : _taskField == 'repeat'
        ? taskRepeats.length
        : _taskField == 'priority'
        ? taskPriorities.length
        : _taskField != null
        ? _dateCandidates.length + 1
        : state.taskItems.length + state.commandItems.length;
    if (count == 0) return;
    final next = (state.highlighted + delta) % count;
    _autocomplete.value = state.copyWith(
      highlighted: next < 0 ? next + count : next,
    );
  }

  void _activateHighlighted() {
    final state = _autocomplete.value;
    if (state == null) return;
    if (_taskField != null) {
      if (_taskField == 'priority') {
        _pickPriority(taskPriorities[state.highlighted]);
      } else if (_taskField == 'repeat') {
        _pickRepeat(taskRepeats[state.highlighted]);
      } else if (state.highlighted < _dateCandidates.length) {
        _pickDate(_dateCandidates[state.highlighted]);
      } else {
        _clearTaskDate();
      }
    } else if (_isMentionLike(state.trigger.kind)) {
      if (state.highlighted < state.mentionItems.length) {
        _selectMention(state.mentionItems[state.highlighted]);
      }
    } else {
      if (state.highlighted < state.taskItems.length) {
        _selectTaskCommand(state.taskItems[state.highlighted]);
      } else if (state.highlighted - state.taskItems.length <
          state.commandItems.length) {
        _selectCommand(
          state.commandItems[state.highlighted - state.taskItems.length],
        );
      }
    }
  }

  // Wiki-links (`[[`) share the mention popup, query, and state machine.
  static bool _isMentionLike(AutocompleteTriggerKind kind) =>
      kind == AutocompleteTriggerKind.mention ||
      kind == AutocompleteTriggerKind.wikiLink;

  Future<void> _selectMention(MentionSuggestion item) async {
    final trigger = _autocomplete.value?.trigger;
    if (trigger == null) return;
    final caret = widget.controller.selection.baseOffset;
    _cancelAutocomplete();
    try {
      await widget.onSelectMention?.call(item);
    } catch (_) {
      return;
    }
    if (!mounted) return;
    // A create row materialises the page first, so the reference inserted
    // below resolves immediately. On failure (or no handler) the old
    // behavior remains: an unresolved chip the user can tap to create.
    String? createdId;
    if (item.create && item.kind == MentionKind.note) {
      createdId = await widget.onCreateNote?.call(item.title);
      if (!mounted) return;
    }
    // One atomic edit: the selection is set over the "@query"/"[[query"
    // trigger text and applyMagic replaces it wholesale (replaceSelection).
    // The old delete-then-insert pair left a revert window between the two
    // controller writes in which a failed round-trip mangled the document.
    widget.controller.selection = TextSelection(
      baseOffset: trigger.start,
      extentOffset: caret,
    );
    final request = switch (item.kind) {
      MentionKind.concept => MagicRequest(
        action: MagicAction.tag,
        value: item.id,
        replaceSelection: true,
      ),
      MentionKind.note =>
        trigger.kind == AutocompleteTriggerKind.wikiLink
            ? MagicRequest(
                action: MagicAction.noteLink,
                id: createdId ?? item.id,
                value: item.title,
                replaceSelection: true,
              )
            : MagicRequest(
                action: MagicAction.mention,
                id: createdId ?? item.id,
                value: item.title,
                replaceSelection: true,
              ),
    };
    widget.controller.applyMagic(request);
    focusNode.requestFocus();
  }

  Future<void> _selectCommand(MagicAction action) async {
    final trigger = _autocomplete.value?.trigger;
    if (trigger == null) return;
    final caret = widget.controller.selection.baseOffset;
    _cancelAutocomplete();
    // Remove the "/query" text first so the chosen action's own handler
    // inserts at the trigger's position, exactly as if invoked from the
    // Magic menu with the cursor there.
    widget.controller.value = widget.controller.value.copyWith(
      text: widget.controller.text.replaceRange(trigger.start, caret, ''),
      selection: TextSelection.collapsed(offset: trigger.start),
      composing: TextRange.empty,
    );
    final handler = widget.onCommandSelected;
    if (handler != null) await handler(action);
    if (mounted) focusNode.requestFocus();
  }

  Future<void> _selectTaskCommand(String command) async {
    final state = _autocomplete.value;
    if (state == null) return;
    final c = widget.controller;
    final caret = c.selection.extentOffset;
    final trigger = state.trigger.start;
    final start =
        caret > trigger &&
            trigger > 0 &&
            c.text[trigger - 1] == ' ' &&
            (c.currentTaskBlockId == null ||
                trigger - 1 >
                    c.document._blockAt(trigger, preferPrevious: true)!.start +
                        1)
        ? trigger - 1
        : trigger;
    final blockId = c.currentTaskBlockId;
    final field = const [
      'due',
      'scheduled',
      'deadline',
      'repeat',
      'priority',
    ].contains(command);
    if (field) {
      _taskField = command == 'deadline' ? 'scheduled' : command;
      _taskFieldBlock = blockId;
      final range = c.document._blockAt(start, preferPrevious: true);
      _taskFieldOffset = start - (range?.start ?? 0);
      _taskFieldText = c.text.replaceRange(start, caret, '');
      _dateInput.clear();
    } else {
      _cancelAutocomplete();
    }
    c.value = TextEditingValue(
      text: c.text.replaceRange(start, caret, ''),
      selection: TextSelection.collapsed(offset: start),
    );
    if (field) {
      _autocomplete.value = state.copyWith(highlighted: 0);
      _ensureOverlay();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _taskField != 'repeat' && _taskField != 'priority') {
          _dateFocus.requestFocus();
        }
      });
      return;
    }
    if (blockId == null) {
      await c.createTaskLine();
    } else if (const ['todo', 'doing', 'done', 'cancel'].contains(command)) {
      await c.setTaskStatus(
        blockId,
        command == 'cancel' ? 'cancelled' : command,
      );
    } else {
      c.setCurrentTaskFields(
        priority: const {
          'a': 'high',
          'b': 'normal',
          'c': 'low',
          'urgent': 'urgent',
        }[command],
      );
    }
    if (mounted) focusNode.requestFocus();
  }

  void _openTaskChip(int index, String command) {
    _cancelAutocomplete();
    final c = widget.controller;
    final end = c.document.blockRanges[index].end;
    c.selection = TextSelection.collapsed(offset: end);
    _autocomplete.value = _AutocompleteState(
      trigger: AutocompleteTrigger(
        kind: AutocompleteTriggerKind.command,
        query: '',
        start: end,
      ),
      mentionItems: const [],
      commandItems: const [],
      taskItems: const [],
      highlighted: 0,
      loading: false,
    );
    unawaited(_selectTaskCommand(command));
  }

  bool _restoreTaskFieldCaret() {
    final c = widget.controller;
    final index = c.document.blocks.indexWhere((b) => b.id == _taskFieldBlock);
    if (index < 0) {
      _cancelAutocomplete();
      return false;
    }
    c.selection = TextSelection.collapsed(
      offset:
          c.document._ranges[index].start +
          _taskFieldOffset.clamp(
            2,
            c.document.blocks[index].visibleText.length,
          ),
    );
    return true;
  }

  void _pickPriority(String priority) {
    if (!_restoreTaskFieldCaret()) return;
    widget.controller.setCurrentTaskFields(priority: priority);
    _cancelAutocomplete();
    focusNode.requestFocus();
  }

  void _pickRepeat(String repeat) {
    if (!_restoreTaskFieldCaret()) return;
    widget.controller.setCurrentTaskFields(recurrence: taskRepeatRule(repeat));
    _cancelAutocomplete();
    focusNode.requestFocus();
  }

  void _pickDate(DateTime date) {
    if (!_restoreTaskFieldCaret()) return;
    final value = date.hour == 0 && date.minute == 0
        ? isoDay(date)
        : '${isoDay(date)}T${localTime(date)}';
    widget.controller.setCurrentTaskFields(
      due: _taskField == 'due' ? value : null,
      scheduled: _taskField == 'scheduled' ? value : null,
    );
    _cancelAutocomplete();
    focusNode.requestFocus();
  }

  void _clearTaskDate() {
    if (!_restoreTaskFieldCaret()) return;
    widget.controller.setCurrentTaskFields(
      due: _taskField == 'due' ? 'none' : null,
      scheduled: _taskField == 'scheduled' ? 'none' : null,
    );
    _cancelAutocomplete();
    focusNode.requestFocus();
  }

  Future<void> _calendarTaskDate() async {
    final date = await showDatePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      initialDate: _dateCandidates.firstOrNull ?? DateTime.now(),
    );
    if (!mounted || _taskField == null) return;
    if (date != null) {
      _pickDate(date);
    } else {
      _dateFocus.requestFocus();
    }
  }

  Widget _taskFieldList(_AutocompleteState state) => TaskFieldList(
    field: _taskField!,
    input: _dateInput,
    focus: _dateFocus,
    dates: _dateCandidates,
    highlighted: state.highlighted,
    onChanged: (_) => _autocomplete.value = state.copyWith(highlighted: 0),
    onSubmitted: (_) => _activateHighlighted(),
    onCalendar: _calendarTaskDate,
    onRepeat: _pickRepeat,
    onPriority: _pickPriority,
    onDate: _pickDate,
    onClear: _clearTaskDate,
  );

  void _cancelAutocomplete() {
    widget.controller.onAutocompleteEnter = null;
    _taskField = null;
    _taskFieldBlock = null;
    _taskFieldText = null;
    _debounce?.cancel();
    _debounce = null;
    _mentionQueryToken++;
    if (_autocomplete.value != null) _autocomplete.value = null;
    _removeOverlay();
  }

  void _ensureOverlay() {
    widget.controller.onAutocompleteEnter = _activateHighlighted;
    if (_overlayEntry != null) return;
    final overlay = Overlay.maybeOf(context);
    if (overlay == null) return;
    _overlayEntry = OverlayEntry(builder: _buildOverlayContent);
    overlay.insert(_overlayEntry!);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _overlayEntry?.markNeedsBuild(),
    );
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  Widget _buildOverlayContent(BuildContext context) =>
      ValueListenableBuilder<_AutocompleteState?>(
        valueListenable: _autocomplete,
        builder: (context, state, _) {
          final editable = _editableIn(_editorKey.currentContext);
          if (state == null || editable == null) return const SizedBox.shrink();
          final overlay =
              Overlay.of(context).context.findRenderObject()! as RenderBox;
          final selection = (_window ?? widget.controller).selection;
          final local = editable.getLocalRectForCaret(
            TextPosition(offset: selection.extentOffset),
          );
          final caret = Rect.fromPoints(
            editable.localToGlobal(local.topLeft, ancestor: overlay),
            editable.localToGlobal(local.bottomRight, ancestor: overlay),
          );
          final count = _isMentionLike(state.trigger.kind)
              ? math.max(1, state.mentionItems.length)
              : _taskField == 'repeat'
              ? taskRepeats.length
              : _taskField == 'priority'
              ? taskPriorities.length
              : _taskField != null
              ? 2 + _dateCandidates.length
              : math.max(1, state.taskItems.length + state.commandItems.length);
          final editorBox =
              _editorKey.currentContext!.findRenderObject()! as RenderBox;
          final editorBottom = editorBox
              .localToGlobal(
                Offset(0, editorBox.size.height),
                ancestor: overlay,
              )
              .dy;
          final safeTop = MediaQuery.paddingOf(context).top;
          final bottom = math.min(
            math.min(
              overlay.size.height - MediaQuery.viewInsetsOf(context).bottom,
              editorBottom,
            ),
            widget.popupBottomY?.call() ?? overlay.size.height,
          );
          final rect = autocompletePopupRect(
            caret.shift(Offset(0, -safeTop)),
            Size(overlay.size.width, math.max(0, bottom - safeTop)),
            Size(
              320,
              _autocompleteRowHeight * math.min(count, _autocompleteMaxVisible),
            ),
          ).shift(Offset(0, safeTop));
          return Positioned.fromRect(
            rect: rect,
            child: TextFieldTapRegion(
              child: Material(
                key: const Key('autocomplete-popup'),
                elevation: 6,
                borderRadius: BorderRadius.circular(kRadiusMedium),
                clipBehavior: Clip.antiAlias,
                child: _taskField != null
                    ? _taskFieldList(state)
                    : _isMentionLike(state.trigger.kind)
                    ? _mentionList(state)
                    : _commandList(state),
              ),
            ),
          );
        },
      );

  Widget _mentionList(_AutocompleteState state) {
    if (state.loading && state.mentionItems.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: LoadingIndicator(size: 20, strokeWidth: 2),
      );
    }
    if (state.mentionItems.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text('No matches'),
      );
    }
    return ListView.builder(
      key: const Key('autocomplete-mention-list'),
      padding: EdgeInsets.zero,
      shrinkWrap: true,
      itemCount: state.mentionItems.length,
      itemBuilder: (context, index) {
        final item = state.mentionItems[index];
        return ListTile(
          key: Key('autocomplete-mention-${item.id}'),
          minTileHeight: 48,
          dense: true,
          tileColor: index == state.highlighted
              ? Theme.of(context).colorScheme.surfaceContainerHighest
              : null,
          leading: Icon(
            item.create
                ? Icons.add_circle_outline
                : item.kind == MentionKind.concept
                ? Icons.tag
                // The note's own kind, so a project reads as a project and an
                // imported article as an article.
                : iconForKind(item.noteKind),
          ),
          title: Text(item.title),
          // A raw id ("md-3b7a2305beedce32") tells the user nothing, and two
          // scraped copies of one page are otherwise identical rows.
          subtitle: Text(
            item.subtitle ?? item.id,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          onTap: () => _selectMention(item),
        );
      },
    );
  }

  Widget _commandList(_AutocompleteState state) {
    if (state.commandItems.isEmpty && state.taskItems.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text('No matching commands'),
      );
    }
    return ListView.builder(
      key: const Key('autocomplete-command-list'),
      padding: EdgeInsets.zero,
      shrinkWrap: true,
      itemCount: state.taskItems.length + state.commandItems.length,
      itemBuilder: (context, index) {
        if (index < state.taskItems.length) {
          final command = state.taskItems[index];
          return ListTile(
            key: Key('autocomplete-task-$command'),
            minTileHeight: 48,
            dense: true,
            selected: state.highlighted == index,
            leading: const Icon(Icons.task_alt),
            title: Text('/$command'),
            onTap: () => _selectTaskCommand(command),
          );
        }
        final action = state.commandItems[index - state.taskItems.length];
        final display = kMagicActionDisplay[action];
        return ListTile(
          key: Key('autocomplete-command-${action.name}'),
          minTileHeight: 48,
          dense: true,
          tileColor: index == state.highlighted
              ? Theme.of(context).colorScheme.surfaceContainerHighest
              : null,
          leading: Icon(display?.$1 ?? Icons.bolt),
          title: Text(display?.$2 ?? action.name),
          onTap: () => _selectCommand(action),
        );
      },
    );
  }

  @override
  void didUpdateWidget(TyLogRichEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_window != null &&
        !identical(oldWidget.controller, widget.controller)) {
      _window!.dispose();
      _attachWindow();
    }
  }

  void _attachWindow() {
    final window = TyLogWindowController(widget.controller);
    _window = window;
    _renderedWindowStart = window.start;
    window.windowRevision.addListener(_windowMoved);
  }

  RenderEditable? _windowEditable() =>
      _editableIn(_windowFieldKey.currentContext);

  RenderEditable? _editableIn(BuildContext? context) {
    RenderEditable? found;
    void visit(Element element) {
      if (found != null) return;
      final render = element.renderObject;
      if (render is RenderEditable) {
        found = render;
        return;
      }
      element.visitChildren(visit);
    }

    if (context is Element) visit(context);
    return found;
  }

  /// Keeps the text under the viewport still when lines move between the
  /// window and the static text above it (the window is the scroll centre).
  void _windowMoved() {
    final window = _window!;
    final oldStart = _renderedWindowStart;
    final newStart = window.start;
    _renderedWindowStart = newStart;
    if (!debugWindowScrollCompensation) return;
    if (!_windowScroll.hasClients || oldStart == newStart) return;
    final offset = _windowScroll.offset;
    if (newStart > oldStart) {
      // Lines [oldStart, newStart) left the top of the old window: measure
      // them there before the field shows the new text.
      final editable = _windowEditable();
      final moved = newStart - oldStart;
      if (editable == null || moved > editable.plainText.length) return;
      final height = editable
          .getLocalRectForCaret(TextPosition(offset: moved))
          .top;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_windowScroll.hasClients) _windowScroll.jumpTo(offset - height);
      });
    } else {
      // Lines [newStart, oldStart) joined the top of the window.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final editable = _windowEditable();
        final moved = oldStart - newStart;
        if (editable == null ||
            !_windowScroll.hasClients ||
            moved > editable.plainText.length) {
          return;
        }
        final height = editable
            .getLocalRectForCaret(TextPosition(offset: moved))
            .top;
        _windowScroll.jumpTo(offset + height);
      });
    }
  }

  @override
  void dispose() {
    _taskScroll.dispose();
    _windowScroll.dispose();
    _window?.dispose();
    _debounce?.cancel();
    _removeOverlay();
    widget.controller.removeListener(_handleControllerChanged);
    focusNode.removeListener(_focusChanged);
    widget.controller.onAutocompleteEnter = null;
    _dateInput.dispose();
    _dateFocus.dispose();
    focusNode.onKeyEvent = null;
    if (widget.focusNode == null) focusNode.dispose();
    super.dispose();
  }

  void _selectAll(EditableTextState state) {
    final window = _window;
    if (window == null) {
      state.selectAll(SelectionChangedCause.toolbar);
      return;
    }
    // The field holds only a window: select the whole document instead.
    widget.controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: widget.controller.text.length,
    );
  }

  Widget _field(
    TextEditingController controller,
    TextStyle? textStyle, {
    required bool expands,
  }) {
    return TextField(
      key: const Key('rich-journal-editor'),
      controller: controller,
      scrollController: _taskScroll,
      focusNode: focusNode,
      expands: expands,
      minLines: null,
      maxLines: null,
      textAlignVertical: TextAlignVertical.top,
      style: textStyle,
      // Without this, TextField forces every line box to the strut
      // height and tall WidgetSpans (inline images) paint over the
      // neighbouring lines; non-forced strut keeps it as a minimum.
      strutStyle: textStyle == null
          ? null
          : StrutStyle.fromTextStyle(textStyle, forceStrutHeight: false),
      decoration: expands
          ? InputDecoration(
              hintText: 'Start writing…',
              contentPadding: EdgeInsets.fromLTRB(
                18,
                18,
                18,
                widget.controller.document.blocks.isNotEmpty &&
                        _taskHasStrip(widget.controller.document.blocks.last)
                    ? math.max(
                        18.0,
                        widget.controller.taskStripHeights[widget
                                .controller
                                .document
                                .blocks
                                .last
                                .id] ??
                            0,
                      )
                    : 18,
              ),
            )
          // The windowed field has no decorator: InputDecorator asks for a
          // dry baseline, a second full text layout on every keystroke
          // (P12). Its hint is painted by _windowedField instead.
          : controller is TyLogWindowController
          ? null
          : InputDecoration.collapsed(
              hintText: widget.controller.text.isEmpty
                  ? 'Start writing…'
                  : null,
            ),
      onTap: () => widget.controller.handleEditorTap(),
      onTapOutside: (_) => focusNode.unfocus(),
      contextMenuBuilder: (context, state) => TextFieldTapRegion(
        child: _checkboxSelection()
            ? TaskStatusMenu(
                anchors: state.contextMenuAnchors,
                onStatus: (status) {
                  final id = widget.controller.currentTaskBlockId;
                  state.hideToolbar();
                  if (id != null) {
                    unawaited(widget.controller.setTaskStatus(id, status));
                  }
                },
              )
            : AdaptiveTextSelectionToolbar.buttonItems(
                anchors: state.contextMenuAnchors,
                buttonItems: [
                  if (!widget.controller.selection.isCollapsed)
                    ContextMenuButtonItem(
                      type: ContextMenuButtonType.copy,
                      onPressed: () {
                        state.hideToolbar();
                        widget.controller.copySelection();
                      },
                    ),
                  if (!widget.controller.selection.isCollapsed)
                    ContextMenuButtonItem(
                      type: ContextMenuButtonType.cut,
                      onPressed: () {
                        state.hideToolbar();
                        widget.controller.cutSelection();
                      },
                    ),
                  ContextMenuButtonItem(
                    type: ContextMenuButtonType.paste,
                    onPressed: () {
                      state.hideToolbar();
                      widget.controller.paste();
                    },
                  ),
                  ContextMenuButtonItem(
                    type: ContextMenuButtonType.selectAll,
                    onPressed: () {
                      _selectAll(state);
                    },
                  ),
                ],
              ),
      ),
    );
  }

  /// Static text above and below a bounded editing window (P12k): 20-line
  /// chunks laid out once; only the window's lines are re-laid out per edit.
  Widget _windowedField(TextStyle? textStyle) {
    final window = _window!;
    final strut = textStyle == null
        ? null
        : StrutStyle.fromTextStyle(textStyle, forceStrutHeight: false);
    Widget chunk(BuildContext context, int start, int end) => _StaticChunk(
      span: widget.controller.rangeSpan(
        context,
        textStyle,
        start: start,
        end: end,
        withComposing: false,
      ),
      strutStyle: strut,
      onTapOffset: (offset) {
        window.placeCaret((start + offset).clamp(start, end));
        focusNode.requestFocus();
      },
    );
    return Actions(
      actions: {
        // The field holds only a window: select-all means the document.
        SelectAllTextIntent: CallbackAction<SelectAllTextIntent>(
          onInvoke: (_) {
            widget.controller.selection = TextSelection(
              baseOffset: 0,
              extentOffset: widget.controller.text.length,
            );
            return null;
          },
        ),
      },
      child: ValueListenableBuilder<int>(
        valueListenable: window.windowRevision,
        builder: (context, _, _) {
          final text = widget.controller.text;
          // Window edges are unit breaks: a line end, or a space inside a
          // long line. A chunk drops its final line break only; the next
          // widget starts on its own line anyway.
          int chunkEnd(int end) =>
              end > 0 && text.codeUnitAt(end - 1) == 0x0A ? end - 1 : end;
          // Line starts of the chunks before the window, and of the chunks
          // after it relative to window.end (stable while typing inside).
          final before = _chunkStarts(text, 0, window.start);
          final afterBase = window.end;
          final afterFrom =
              afterBase < text.length && text.codeUnitAt(afterBase) == 0x0A
              ? afterBase + 1
              : afterBase;
          final after = afterFrom < text.length
              ? _chunkStarts(
                  text,
                  afterFrom,
                  text.length,
                ).map((offset) => offset - afterBase).toList()
              : const <int>[];
          // The window is the scroll centre: it is always built (so the
          // field exists for the IME) and static text above it grows upwards.
          return CustomScrollView(
            controller: _windowScroll,
            center: const ValueKey('editing-window'),
            slivers: [
              const SliverToBoxAdapter(child: SizedBox(height: 18)),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                sliver: SliverList.builder(
                  itemCount: before.length,
                  // Built from the window upwards: item 0 is the last chunk.
                  // Stable keys: re-centring shifts indices, not content;
                  // reuse chunks by offset.
                  findChildIndexCallback: (key) {
                    if (key is! ValueKey<int>) return null;
                    final at = before.indexOf(key.value);
                    return at < 0 ? null : before.length - 1 - at;
                  },
                  itemBuilder: (context, i) {
                    final at = before.length - 1 - i;
                    return KeyedSubtree(
                      key: ValueKey<int>(before[at]),
                      child: chunk(
                        context,
                        before[at],
                        chunkEnd(
                          at + 1 < before.length
                              ? before[at + 1]
                              : window.start,
                        ),
                      ),
                    );
                  },
                ),
              ),
              SliverPadding(
                key: const ValueKey('editing-window'),
                padding: const EdgeInsets.symmetric(horizontal: 18),
                sliver: SliverToBoxAdapter(
                  child: KeyedSubtree(
                    key: _windowFieldKey,
                    child: Stack(
                      children: [
                        _field(window, textStyle, expands: false),
                        ListenableBuilder(
                          listenable: window,
                          builder: (context, _) => window.main.text.isEmpty
                              ? IgnorePointer(
                                  child: Text(
                                    'Start writing…',
                                    style: textStyle?.copyWith(
                                      color: Theme.of(context).hintColor,
                                    ),
                                  ),
                                )
                              : const SizedBox.shrink(),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                sliver: SliverList.builder(
                  itemCount: after.length,
                  // Stable keys: reuse the "after" chunks by their negative
                  // offset so they survive re-centre shifts.
                  findChildIndexCallback: (key) {
                    if (key is! ValueKey<int>) return null;
                    final at = after.indexOf(-1 - key.value);
                    return at < 0 ? null : at;
                  },
                  itemBuilder: (context, i) {
                    final base = window.end;
                    final length = widget.controller.text.length;
                    return KeyedSubtree(
                      key: ValueKey<int>(-1 - after[i]),
                      child: chunk(
                        context,
                        base + after[i],
                        i + 1 < after.length
                            ? chunkEnd(base + after[i + 1])
                            : length,
                      ),
                    );
                  },
                ),
              ),
              SliverFillRemaining(
                hasScrollBody: false,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    window.placeCaret(widget.controller.text.length);
                    focusNode.requestFocus();
                  },
                  child: const SizedBox(height: 18),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  RelativeRect _menuPositionBelow(BuildContext context, GlobalKey key) {
    final button = key.currentContext!.findRenderObject()! as RenderBox;
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final topLeft = button.localToGlobal(Offset.zero, ancestor: overlay);
    final bottomRight = button.localToGlobal(
      button.size.bottomRight(Offset.zero),
      ancestor: overlay,
    );
    return RelativeRect.fromRect(
      Rect.fromPoints(topLeft, bottomRight),
      Offset.zero & overlay.size,
    );
  }

  Future<void> _showHeadingMenu(BuildContext context) async {
    final level = await showMenu<int>(
      context: context,
      position: _menuPositionBelow(context, _headingButtonKey),
      items: const [
        PopupMenuItem(value: 2, child: Text('Heading 2')),
        PopupMenuItem(value: 3, child: Text('Heading 3')),
        PopupMenuItem(value: 4, child: Text('Heading 4')),
      ],
    );
    if (level != null) widget.controller.setHeading(level: level);
    if (mounted) focusNode.requestFocus();
  }

  // Built from kHighlightChoices — the single source of truth shared with the
  // Magic/slash colour picker — so this menu and that one can never drift.
  Future<void> _showHighlightMenu(BuildContext context) async {
    final fill = await showMenu<String>(
      context: context,
      position: _menuPositionBelow(context, _highlightButtonKey),
      items: [
        for (final (choiceFill, label) in kHighlightChoices)
          PopupMenuItem(
            value: choiceFill,
            child: Row(
              children: [
                Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    color: highlightSwatchColor(choiceFill),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Theme.of(context).colorScheme.outline,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text(label),
              ],
            ),
          ),
      ],
    );
    if (fill != null) {
      // Same three-way contract as applyMagic's MagicAction.highlight case:
      // '' is Typst's default fill, kHighlightNone clears it, anything else
      // is a verbatim fill expression.
      widget.controller.setHighlight(fill == kHighlightNone ? null : fill);
    }
    if (mounted) focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final textStyle = Theme.of(
      context,
    ).textTheme.bodyLarge?.copyWith(height: 1.55);
    return Column(
      children: [
        Expanded(
          child: NotificationListener<ScrollNotification>(
            onNotification: (_) {
              _overlayEntry?.markNeedsBuild();
              return false;
            },
            child: LayoutBuilder(
              builder: (context, constraints) {
                widget.controller.imageContentWidth =
                    constraints.maxWidth - (_window == null ? 36 : 0);
                return ListenableBuilder(
                  listenable: widget.controller,
                  builder: (context, _) => Stack(
                    clipBehavior: Clip.hardEdge,
                    children: [
                      Positioned.fill(
                        child: SizedBox(
                          key: _editorKey,
                          child: _window == null
                              ? _field(
                                  widget.controller,
                                  textStyle,
                                  expands: true,
                                )
                              : _windowedField(textStyle),
                        ),
                      ),
                      Positioned.fill(
                        child: Flow(
                          delegate: _TaskStripFlow(
                            controller: widget.controller,
                            window: _window,
                            editable: () =>
                                _editableIn(_editorKey.currentContext),
                            origin: () =>
                                _editorKey.currentContext?.findRenderObject()
                                    as RenderBox?,
                            repaint: Listenable.merge([
                              widget.controller,
                              _taskScroll,
                            ]),
                          ),
                          children: [
                            for (final range
                                in widget.controller.document._ranges)
                              if (_taskHasStrip(
                                widget.controller.document.blocks[range.index],
                              ))
                                TaskChipStrip(
                                  task: taskFromSource(
                                    widget.controller.document.sourceFor(
                                      widget
                                          .controller
                                          .document
                                          .blocks[range.index]
                                          .id,
                                    ),
                                  ),
                                  onCommand: (command) =>
                                      _openTaskChip(range.index, command),
                                ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
        // AnimatedSize slides the dock open/closed instead of snapping the
        // text field by 48px on every focus change. In flow on purpose:
        // overlaying would cover the last line of text.
        AnimatedSize(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          alignment: Alignment.topCenter,
          child: !focusNode.hasFocus
              ? const SizedBox(width: double.infinity, height: 0)
              : TextFieldTapRegion(
                  child: SafeArea(
                    top: false,
                    child: SizedBox(
                      height: 48,
                      child: ListenableBuilder(
                        listenable: widget.controller,
                        builder: (context, _) => ListView(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          scrollDirection: Axis.horizontal,
                          children: [
                            IconButton(
                              tooltip: 'Undo',
                              onPressed: widget.controller.canUndo
                                  ? widget.controller.undo
                                  : null,
                              icon: const Icon(Icons.undo),
                            ),
                            IconButton(
                              tooltip: 'Redo',
                              onPressed: widget.controller.canRedo
                                  ? widget.controller.redo
                                  : null,
                              icon: const Icon(Icons.redo),
                            ),
                            IconButton(
                              key: _headingButtonKey,
                              tooltip: 'Heading 1',
                              onPressed: widget.controller.setHeading,
                              onLongPress: () => _showHeadingMenu(context),
                              icon: Text(
                                'H1',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ),
                            IconButton(
                              tooltip: 'More heading levels',
                              onPressed: () => _showHeadingMenu(context),
                              icon: const Icon(Icons.arrow_drop_down),
                            ),
                            // ponytail: two loops, not one — the highlight button sits
                            // mid-row and carries a key + onLongPress. Order here is
                            // the on-screen order; do not merge the loops.
                            for (final (tip, press, icon)
                                in <(String, VoidCallback, IconData)>[
                                  (
                                    'Bold',
                                    widget.controller.toggleBold,
                                    Icons.format_bold,
                                  ),
                                  (
                                    'Italic',
                                    widget.controller.toggleItalic,
                                    Icons.format_italic,
                                  ),
                                  (
                                    'Strikethrough',
                                    widget.controller.toggleStrike,
                                    Icons.format_strikethrough,
                                  ),
                                  (
                                    'Underline',
                                    widget.controller.toggleUnderline,
                                    Icons.format_underline,
                                  ),
                                  (
                                    'Monospace',
                                    widget.controller.toggleMono,
                                    Icons.code,
                                  ),
                                ])
                              IconButton(
                                tooltip: tip,
                                onPressed: press,
                                icon: Icon(icon),
                              ),
                            IconButton(
                              key: _highlightButtonKey,
                              tooltip: 'Highlight (long-press for colors)',
                              onPressed: widget.controller.toggleHighlight,
                              onLongPress: () => _showHighlightMenu(context),
                              icon: const Icon(Icons.border_color),
                            ),
                            for (final (tip, press, icon)
                                in <(String, VoidCallback, IconData)>[
                                  (
                                    'Bulleted list',
                                    widget.controller.setBulletList,
                                    Icons.format_list_bulleted,
                                  ),
                                  (
                                    'Numbered list',
                                    widget.controller.setNumberedList,
                                    Icons.format_list_numbered,
                                  ),
                                  (
                                    'Clear formatting',
                                    widget.controller.clearFormatting,
                                    Icons.format_clear,
                                  ),
                                ])
                              IconButton(
                                tooltip: tip,
                                onPressed: press,
                                icon: Icon(icon),
                              ),
                            IconButton(
                              tooltip: 'Insert',
                              onPressed: () async {
                                try {
                                  await widget.onInsert();
                                } finally {
                                  if (mounted) focusNode.requestFocus();
                                }
                              },
                              icon: const Icon(Icons.add_circle_outline),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}

/// Renders an image atom (`#image(...)`) as a real inline picture, loaded from
/// the vault via the controller's cached [bytes] future. While loading it shows
/// a compact placeholder; on a missing file / decode error it falls back to
/// [fallback] (the original path chip) so a dead reference is still visible.
class _InlineImage extends StatefulWidget {
  const _InlineImage({
    super.key,
    required this.bytes,
    required this.fallback,
    required this.onTap,
    required this.id,
    this.controller,
    this.layout,
    this.contentWidth,
  });

  final String id;
  final TyLogEditingController? controller;
  final (int, String)? layout;
  final double? contentWidth;
  final Future<Uint8List?> bytes;
  final Widget fallback;
  final VoidCallback? onTap;

  @override
  State<_InlineImage> createState() => _InlineImageState();
}

class _InlineImageState extends State<_InlineImage> {
  final LayerLink _link = LayerLink();
  final GlobalKey _targetKey = GlobalKey();
  OverlayEntry? _toolbar;
  bool _editing = false;
  Uint8List? _decodedData;

  @override
  void initState() {
    super.initState();
    widget.controller?.addListener(_changed);
  }

  @override
  void didUpdateWidget(_InlineImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.bytes != widget.bytes) _decodedData = null;
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?.removeListener(_changed);
      widget.controller?.addListener(_changed);
      _dismiss();
    }
  }

  void _changed() {
    if (!_editing) _dismiss();
  }

  void _dismiss() {
    if (_toolbar == null) return;
    _toolbar!.remove();
    _toolbar!.dispose();
    _toolbar = null;
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.controller?.removeListener(_changed);
    _toolbar?.remove();
    _toolbar?.dispose();
    super.dispose();
  }

  void _edit({int? width, String? align, int move = 0, bool delete = false}) {
    _editing = true;
    widget.controller!.editImage(
      widget.id,
      width: width,
      align: align,
      move: move,
      delete: delete,
    );
    _editing = false;
    if (delete) {
      _dismiss();
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _toolbar == null) return;
        _dismiss();
        _select();
      });
    }
  }

  Future<void> _crop() async {
    final controller = widget.controller!;
    final document = controller.document;
    final source = controller.protectedSource(widget.id);
    final path = _imageAtomPath(source)!;
    final bytes = _decodedData!;
    _dismiss();
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (context) => ImageCropPage(
          bytes: bytes,
          onError: controller.onError,
          onDone: (bytes) async {
            if (!mounted ||
                !identical(controller.document, document) ||
                controller.protectedSource(widget.id) != source) {
              throw StateError('Image changed while cropping');
            }
            final next = await controller.imageWriter!(path, bytes);
            if (!mounted ||
                !identical(controller.document, document) ||
                controller.protectedSource(widget.id) != source) {
              throw StateError('Image changed while cropping');
            }
            controller.editImage(widget.id, path: next);
          },
        ),
      ),
    );
  }

  void _select() {
    if (widget.controller == null) {
      widget.onTap?.call();
      return;
    }
    if (_toolbar != null) return;
    final box = _targetKey.currentContext!.findRenderObject()! as RenderBox;
    final overlayBox =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final origin = box.localToGlobal(
      Offset(0, box.size.height),
      ancestor: overlayBox,
    );
    final toolbarWidth = math.min(MediaQuery.sizeOf(context).width - 16, 360.0);
    final dx =
        origin.dx.clamp(
          8.0,
          math.max(8.0, overlayBox.size.width - toolbarWidth - 8),
        ) -
        origin.dx;
    final dy =
        origin.dy + 148 >
            overlayBox.size.height - MediaQuery.viewInsetsOf(context).bottom
        ? -box.size.height - 148.0
        : 4.0;
    final blocks = widget.controller!.document.blocks;
    final index = blocks.indexWhere(
      (block) => block.parts.any((part) => part.id == widget.id),
    );
    final alone =
        index >= 0 &&
        blocks[index].style == TyLogBlockStyle.paragraph &&
        blocks[index].parts
                .where((part) => part.text.trim().isNotEmpty)
                .length ==
            1;
    _toolbar = OverlayEntry(
      builder: (context) => Positioned(
        width: math.min(MediaQuery.sizeOf(context).width - 16, 360),
        child: CompositedTransformFollower(
          link: _link,
          showWhenUnlinked: false,
          targetAnchor: Alignment.bottomLeft,
          followerAnchor: Alignment.topLeft,
          offset: Offset(dx, dy),
          child: TextFieldTapRegion(
            child: TapRegion(
              groupId: this,
              child: Material(
                elevation: 6,
                borderRadius: BorderRadius.circular(kRadiusSmall),
                child: Wrap(
                  children: [
                    if (_decodedData != null &&
                        widget.controller!.imageWriter != null)
                      IconButton(
                        tooltip: 'Crop',
                        onPressed: _crop,
                        icon: const Icon(Icons.crop),
                      ),
                    for (final (label, width) in [
                      ('S', 33),
                      ('M', 60),
                      ('Full', 100),
                    ])
                      TextButton(
                        onPressed: () => _edit(width: width),
                        child: Text(label),
                      ),
                    for (final (align, icon) in [
                      ('left', Icons.format_align_left),
                      ('center', Icons.format_align_center),
                      ('right', Icons.format_align_right),
                    ])
                      IconButton(
                        tooltip: 'Align $align',
                        onPressed: () => _edit(align: align),
                        icon: Icon(icon),
                      ),
                    for (final (label, icon, action)
                        in <(String, IconData, VoidCallback)>[
                          (
                            'Move image up',
                            Icons.arrow_upward,
                            () => _edit(move: -1),
                          ),
                          (
                            'Move image down',
                            Icons.arrow_downward,
                            () => _edit(move: 1),
                          ),
                          (
                            'Delete image',
                            Icons.delete_outline,
                            () => _edit(delete: true),
                          ),
                          (
                            'Open image',
                            Icons.open_in_new,
                            () {
                              _dismiss();
                              widget.onTap?.call();
                            },
                          ),
                        ])
                      IconButton(
                        tooltip: label,
                        onPressed:
                            label == 'Move image up' &&
                                    (!alone || index == 0) ||
                                label == 'Move image down' &&
                                    (!alone || index == blocks.length - 1)
                            ? null
                            : action,
                        icon: Icon(icon),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    Overlay.of(context).insert(_toolbar!);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final layout = widget.layout;
    final contentWidth =
        widget.contentWidth ?? MediaQuery.sizeOf(context).width;
    final width = layout == null ? null : contentWidth * layout.$1 / 100;
    final maxHeight =
        MediaQuery.sizeOf(context).height * (layout == null ? 0.4 : 0.6);
    final picture = FutureBuilder<Uint8List?>(
      future: widget.bytes,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const SizedBox(
            height: 18,
            width: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          );
        }
        final data = snapshot.data;
        if (data == null || data.isEmpty) return widget.fallback;
        return ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: width ?? MediaQuery.sizeOf(context).width * 0.7,
            maxHeight: maxHeight,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(kRadiusSmall),
            child: Image.memory(
              data,
              width: width,
              fit: BoxFit.contain,
              semanticLabel: 'Image',
              frameBuilder: (context, child, frame, synchronous) {
                if (frame != null || synchronous) _decodedData = data;
                return child;
              },
              // Bound decoding to the display width, including for large originals.
              cacheWidth:
                  ((layout == null
                              ? MediaQuery.sizeOf(context).width
                              : contentWidth) *
                          MediaQuery.devicePixelRatioOf(context))
                      .round(),
              errorBuilder: (context, _, _) {
                _decodedData = null;
                return widget.fallback;
              },
            ),
          ),
        );
      },
    );
    final selectable = TapRegion(
      groupId: this,
      onTapOutside: (_) => _dismiss(),
      child: CompositedTransformTarget(
        key: _targetKey,
        link: _link,
        child: GestureDetector(
          onTap: widget.controller != null || widget.onTap != null
              ? _select
              : null,
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(
                color: _toolbar == null
                    ? Colors.transparent
                    : Theme.of(context).colorScheme.primary,
                width: 2,
              ),
            ),
            child: picture,
          ),
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: layout == null
          ? selectable
          : SizedBox(
              width: contentWidth,
              child: Align(
                alignment: switch (layout.$2) {
                  'left' => Alignment.centerLeft,
                  'right' => Alignment.centerRight,
                  _ => Alignment.center,
                },
                child: selectable,
              ),
            ),
    );
  }
}

class _ProtectedChip extends StatelessWidget {
  const _ProtectedChip({
    required this.label,
    required this.block,
    required this.onTap,
    required this.icon,
    this.unresolved = false,
    this.textStyle,
  });

  final String label;
  final bool block;
  final VoidCallback? onTap;
  final IconData icon;
  final bool unresolved;

  /// The style of the text run this chip sits in. A `WidgetSpan` does not
  /// inherit the surrounding `TextSpan` style — without this the label falls
  /// back to the Material default and the chip reads as a foreign object
  /// dropped into the sentence. Null for block chips, which stand alone.
  final TextStyle? textStyle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final inline = textStyle?.copyWith(height: 1.55);
    final radius = BorderRadius.circular(block ? kRadiusMedium : kRadiusSmall);
    return Semantics(
      button: onTap != null,
      label: '$label, protected Typst',
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: block ? 0 : 1,
          vertical: block ? 2 : 0,
        ),
        child: Material(
          // Inline: a tint that sits under the prose rather than an opaque
          // block that interrupts it.
          color: block
              ? scheme.surfaceContainerHighest
              : scheme.primary.withValues(alpha: 0.08),
          borderRadius: radius,
          child: InkWell(
            onTap: onTap,
            borderRadius: radius,
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: block ? 12 : 4,
                vertical: block ? 10 : 1,
              ),
              // Bounded (not single-line-ellipsized) so a long extracted
              // label — e.g. a hand-authored `#step[...]` body — stays fully
              // readable instead of being cut to "…" after a few words.
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.sizeOf(context).width * 0.7,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  // Inline chips are one line — center the icon with the text
                  // so it doesn't float above the baseline. Block chips can
                  // wrap to several lines, so keep their icon on the first.
                  crossAxisAlignment: block
                      ? CrossAxisAlignment.start
                      : CrossAxisAlignment.center,
                  children: [
                    Icon(
                      icon,
                      // Scales with the prose instead of fixing a 16px icon
                      // into a possibly-smaller run.
                      size: block ? 16 : (inline?.fontSize ?? 16) * 0.85,
                      color: block ? null : scheme.primary,
                    ),
                    SizedBox(width: block ? 5 : 3),
                    Flexible(
                      child: Text(
                        label,
                        style: unresolved
                            ? (inline ?? const TextStyle()).copyWith(
                                color: scheme.onSurfaceVariant,
                                decoration: TextDecoration.underline,
                                decorationStyle: TextDecorationStyle.dashed,
                              )
                            : inline,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

TyLogBlock _parseBlock(ControlledBlock block, String separator, int index) {
  final source = block.source;
  final trimmed = source.trimLeft();
  final id = 'block-$index-${source.hashCode}';
  if (block.kind == ControlledBlockKind.task) {
    final taskId = taskField(source, 'id');
    final taskText = taskField(source, 'text');
    if (taskId != null && taskText != null) {
      final glyph = switch (taskField(source, 'status')) {
        'doing' => taskDoingGlyph,
        'done' => taskCheckedGlyph,
        'cancelled' => taskCancelledGlyph,
        _ => taskUncheckedGlyph,
      };
      return TyLogBlock(
        id: id,
        style: TyLogBlockStyle.taskLine,
        parts: [TyLogInline.text('$glyph $taskText')],
        originalSource: source,
        separator: separator,
      );
    }
    return TyLogBlock(
      id: id,
      style: TyLogBlockStyle.protected,
      parts: const [],
      originalSource: source,
      separator: separator,
      protectedLabel: 'Task: ${controlledBlockPreview(block)}',
    );
  }
  if (block.kind == ControlledBlockKind.table ||
      block.kind == ControlledBlockKind.equation ||
      block.kind == ControlledBlockKind.raw) {
    return TyLogBlock(
      id: id,
      style: TyLogBlockStyle.protected,
      parts: const [],
      originalSource: source,
      separator: separator,
      protectedLabel: switch (block.kind) {
        ControlledBlockKind.table => 'Table',
        ControlledBlockKind.equation => 'Equation',
        _ => 'Custom Typst',
      },
    );
  }

  var style = TyLogBlockStyle.paragraph;
  var body = trimmed;
  var headingLevel = 1;
  if (block.kind == ControlledBlockKind.heading) {
    style = TyLogBlockStyle.heading;
    final marker = RegExp(r'^=+').firstMatch(trimmed)!.group(0)!;
    headingLevel = marker.length;
    body = trimmed.replaceFirst(RegExp(r'^=+\s*'), '');
  } else if (block.kind == ControlledBlockKind.list) {
    // Block style drives the toolbar state only; the glyph is decided per line
    // below, because a Logseq export routinely mixes `-` and `+` inside one
    // block and the first line does not speak for the rest.
    style = RegExp(r'^(?:\d+\. |\+ )').hasMatch(trimmed)
        ? TyLogBlockStyle.numberedList
        : TyLogBlockStyle.bulletList;
    var number = 1;
    // Indent is content: it is what makes a Typst list nest. Keep it in front
    // of the glyph so the serializer can put the `- `/`+ ` back where it was —
    // stripping it here is what used to turn `  - b` into `- - b` on save.
    // Read from `source`, not `trimmed`: a block may now start on an indented
    // line (a plain bullet following a list-item task).
    //
    // A line with no marker is a *continuation* of the item above it — a
    // Logseq block is often several lines long. Leaving it glyph-less is what
    // makes the round-trip work: glyph presence now means marker presence, so
    // the serializer adds a marker back to exactly the lines that had one.
    // Previously the marker was optional on both sides, so every wrapped line
    // grew a bullet it never had (6152 lines across 457 imported notes).
    body = source
        .split('\n')
        .map((line) {
          final marker = _listMarker.firstMatch(line);
          if (marker == null) return line;
          final indent = marker.group(1)!;
          final content = line.substring(marker.end);
          final ordered = marker.group(2) == '+' || marker.group(3) != null;
          return ordered ? '$indent${number++}. $content' : '$indent• $content';
        })
        .join('\n');
  }
  final parts = _parseInline(body);
  if (parts == null) {
    return TyLogBlock(
      id: id,
      style: TyLogBlockStyle.protected,
      parts: const [],
      originalSource: source,
      separator: separator,
      protectedLabel: 'Custom Typst',
    );
  }
  for (var i = 0; i < parts.length; i++) {
    final part = parts[i];
    if (part.isAtom && _imageAtomPath(part.source!) != null) {
      parts[i] = TyLogInline.atom(
        source: part.source,
        label: part.label,
        id: '$id-${part.id}',
      );
    }
  }
  return TyLogBlock(
    id: id,
    style: style,
    parts: parts,
    originalSource: source,
    separator: separator,
    headingLevel: headingLevel,
  );
}

/// Pragmatic email matcher (not full RFC 5322): a local part, `@`, a dotted
/// domain with a 2+ letter TLD. Shared by parse-time and type-time detection.
final _emailPattern = RegExp(
  r'[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)*\.[A-Za-z]{2,}',
);

/// A character allowed in an email local part — used to find the true start of
/// an address so detection never begins mid-token.
bool _emailLocalChar(int c) =>
    (c >= 48 && c <= 57) ||
    (c >= 65 && c <= 90) ||
    (c >= 97 && c <= 122) ||
    c == 46 || // .
    c == 95 || // _
    c == 37 || // %
    c == 43 || // +
    c == 45; // -

/// Whether [c] ends a token such that a following `@key` is a Typst citation
/// (start-of-line, whitespace, `[`, or `(`).
bool _citationBreakBefore(int c) =>
    c == 32 || c == 9 || c == 10 || c == 13 || c == 91 || c == 40;

/// The Typst source for a bare email rendered as a clickable mailto link chip.
String mailtoLinkSource(String address) =>
    '#link("mailto:$address")[${address.replaceAll('@', r'\@')}]';

List<TyLogInline>? _parseInline(
  String source, {
  TyLogInlineStyle inherited = const TyLogInlineStyle(),
}) {
  final parts = <TyLogInline>[];
  final plain = StringBuffer();
  var atom = 0;
  void flush() {
    if (plain.isEmpty) return;
    parts.add(TyLogInline.text(plain.toString(), style: inherited));
    plain.clear();
  }

  for (var i = 0; i < source.length;) {
    if (source.codeUnitAt(i) == 92 && i + 1 < source.length) {
      plain.write(source[i + 1]);
      i += 2;
      continue;
    }
    final styled = <(String, TyLogInlineStyle Function(TyLogInlineStyle))>[
      ('#strong[', (s) => s.copyWith(bold: true)),
      ('#emph[', (s) => s.copyWith(italic: true)),
      ('#strike[', (s) => s.copyWith(strike: true)),
      ('#underline[', (s) => s.copyWith(underline: true)),
    ];
    var consumedStyle = false;
    for (final entry in styled) {
      if (!source.startsWith(entry.$1, i)) continue;
      final open = i + entry.$1.length - 1;
      final close = _squareEnd(source, open);
      if (close == null) return null;
      final nested = _parseInline(
        source.substring(open + 1, close - 1),
        inherited: entry.$2(inherited),
      );
      if (nested == null) return null;
      flush();
      parts.addAll(nested);
      i = close;
      consumedStyle = true;
      break;
    }
    if (consumedStyle) continue;

    final delimiter = source[i];
    if (delimiter == '*' || delimiter == '_') {
      final close = _unescapedIndexOf(source, delimiter, i + 1);
      if (close > i + 1) {
        final nested = _parseInline(
          source.substring(i + 1, close),
          inherited: inherited.copyWith(
            bold: inherited.bold || delimiter == '*',
            italic: inherited.italic || delimiter == '_',
          ),
        );
        if (nested == null) return null;
        flush();
        parts.addAll(nested);
        i = close + 1;
        continue;
      }
    }

    if (delimiter == '`') {
      // Raw Typst content: literal, no recursive markup parsing inside.
      final close = source.indexOf('`', i + 1);
      if (close > i) {
        flush();
        parts.add(
          TyLogInline.text(
            source.substring(i + 1, close),
            style: inherited.copyWith(mono: true),
          ),
        );
        i = close + 1;
        continue;
      }
    }

    final highlightMatch = _tryParseHighlight(source, i, inherited);
    if (highlightMatch != null) {
      flush();
      parts.addAll(highlightMatch.$2);
      i = highlightMatch.$1;
      continue;
    }

    // Bare email -> a clickable mailto link chip. Detected only at a true
    // local-part boundary so we grab the whole address (and never a fragment
    // of a longer token). A bare `@domain` in Typst is a dangling reference —
    // this is why unescaped emails used to split into a broken chip.
    if (i == 0 || !_emailLocalChar(source.codeUnitAt(i - 1))) {
      final email = _emailPattern.matchAsPrefix(source, i);
      if (email != null) {
        final address = email.group(0)!;
        flush();
        parts.add(
          TyLogInline.atom(
            source: mailtoLinkSource(address),
            label: address,
            id: 'atom-${source.hashCode}-${atom++}',
          ),
        );
        i = email.end;
        continue;
      }
    }

    // The label part accepts `\]` and one level of nesting. `[^\]]*` stopped at
    // the first `]` whatever preceded it, so a label like
    // `[... \[2026 Edition\]]` matched only half of itself and left a stray
    // `]` behind — the round-trip guard then saw a mismatch and silently
    // reverted the user's edit. Three such labels in the vault, in two notes:
    // escaped brackets from the importer, and one real `#link(...)[#link(...)[…]]`.
    final atomMatch = RegExp(
      r'^(#(?:link|tylog\.(?:ref-note|date-ref|attachment))\([^\n]*?\)'
      r'\[(?:\\.|[^\[\]]|\[(?:\\.|[^\[\]])*\])*\]'
      r'|#tylog\.tag\("(?:\\.|[^"])*"\)|#cite\([^)]*\)|#[iI]mage\([^)]*\)'
      r'|@[A-Za-z0-9_.:+-]+)',
    ).firstMatch(source.substring(i));
    if (atomMatch != null) {
      final raw = atomMatch.group(0)!;
      // A citation `@key` is only a reference at a break (start, whitespace,
      // `[`, `(`) — mirroring `_previewSource`. Without this guard the `@domain`
      // half of an email `foo@bar.com` is swallowed as a citation.
      final isCitation = raw.startsWith('@');
      if (!isCitation ||
          i == 0 ||
          _citationBreakBefore(source.codeUnitAt(i - 1))) {
        flush();
        parts.add(
          TyLogInline.atom(
            source: raw,
            label: _atomLabel(raw),
            id: 'atom-${source.hashCode}-${atom++}',
          ),
        );
        i += raw.length;
        continue;
      }
    }
    if (source.codeUnitAt(i) == 35) {
      // Any other cleanly delimited call (e.g. #footnote[…], #link("url"))
      // becomes an inline protected atom so the surrounding prose stays
      // editable instead of collapsing the whole paragraph.
      final end = inlineCallEnd(source, i);
      if (end == null) return null;
      final raw = source.substring(i, end);
      flush();
      parts.add(
        TyLogInline.atom(
          source: raw,
          label: _atomLabel(raw),
          id: 'atom-${source.hashCode}-${atom++}',
        ),
      );
      i = end;
      continue;
    }
    plain.writeCharCode(source.codeUnitAt(i));
    i++;
  }
  flush();
  return _normalize(parts);
}

/// Whether [source] is one of the app's own navigable reference calls
/// (link, tag, citation, mention, …) rather than a generic unknown wrapper
/// call. Reference atoms stay chips in Read mode; generic wrappers unwrap
/// to their inner text since there's nowhere to navigate to.
bool _isReferenceAtom(String source) =>
    source.startsWith('@') ||
    source.startsWith('#link(') ||
    source.startsWith('#tylog.ref-note(') ||
    source.startsWith('#tylog.date-ref(') ||
    source.startsWith('#tylog.attachment(') ||
    source.startsWith('#tylog.tag(') ||
    source.startsWith('#cite(') ||
    source.startsWith('#image(') ||
    source.startsWith('#Image(');

(int, String)? _imageLayout(String source) {
  final match = RegExp(
    r'#align\((left|center|right),\s*image\("(?:\\.|[^"])*",\s*width:\s*(33|60|100)%\)\)',
  ).firstMatch(source);
  return match == null ? null : (int.parse(match.group(2)!), match.group(1)!);
}

/// Asset path for a bare image or an image attachment; null for other atoms.
String? _imageAtomPath(String source) {
  final image = RegExp(r'^#[iI]mage\("((?:\\.|[^"])*)"').firstMatch(source);
  if (image != null) return unescapeTypstString(image.group(1)!);
  if (source.startsWith('#tylog.attachment(') &&
      RegExp(r'kind:\s*"image"').hasMatch(source)) {
    final path = RegExp(r'"((?:\\.|[^"])*)"').firstMatch(source)?.group(1);
    if (path != null) return unescapeTypstString(path);
  }
  return null;
}

/// Inner content of a `#name(...)?[body]` call's trailing bracket group, or
/// the raw source unchanged if it has no bracket body.
String _atomBody(String source) {
  final open = source.indexOf('[');
  if (open < 0) return source;
  final close = _squareEnd(source, open);
  if (close == null) return source;
  return source.substring(open + 1, close - 1);
}

/// A pasted URL usually arrives as its own label, so the chip ends up holding
/// the whole address — 827 of them in this vault, the longest 258 characters.
/// The chip is deliberately unbounded (a hand-authored `#step[...]` body must
/// stay readable), so a raw URL wrapped into a multi-line slab 70% of the
/// viewport wide, mid-sentence. Show what identifies the link instead: host,
/// plus a trimmed path when there is room.
String _shortenUrlLabel(String label) {
  if (label.length <= 48) return label;
  final uri = Uri.tryParse(label);
  if (uri == null || !uri.hasAuthority) return label;
  final host = uri.host.replaceFirst(RegExp(r'^www\.'), '');
  final path = uri.path.replaceFirst(RegExp(r'/$'), '');
  if (path.isEmpty || path == '/') return host;
  final tail = path.split('/').where((s) => s.isNotEmpty).last;
  return tail.length > 32 ? '$host/${tail.substring(0, 31)}…' : '$host/$tail';
}

String _atomLabel(String source) {
  // Same bracket grammar the atom scanner uses: `\]` and one level of nesting.
  // With a plain `[^\]]*` a title like `… \[2026 Edition\]` matched nothing at
  // all, and the chip fell through to the quoted-string branch and displayed
  // the raw note id instead of the title.
  final content = RegExp(
    r'\[((?:\\.|[^\[\]]|\[(?:\\.|[^\[\]])*\])*)\]$',
  ).firstMatch(source)?.group(1);
  if (content != null && content.isNotEmpty) {
    final label = unescapeMarkup(content);
    // Only for links: a long label on any other atom is authored text.
    return source.startsWith('#link(') ? _shortenUrlLabel(label) : label;
  }
  final quoted = RegExp(r'"((?:\\.|[^"])*)"').firstMatch(source)?.group(1);
  if (quoted != null) {
    return unescapeMarkup(quoted.replaceAll(r'\"', '"'));
  }
  if (source.startsWith('@')) return source.substring(1);
  if (source.startsWith('#cite(')) {
    return source.substring(6, source.length - 1);
  }
  return source.startsWith('#image') ? 'Image' : 'Reference';
}

/// The chip icon for an inline atom, by what it points at: email vs web link,
/// tag, date, attachment, citation, and — via [resolvedKind] against the vault
/// index — the referenced note's kind (person/place/project/…).
IconData _atomIcon(String source, {String? resolvedKind}) {
  if (source.startsWith('#link(')) {
    final url =
        RegExp(r'^#link\("((?:\\.|[^"])*)"').firstMatch(source)?.group(1) ?? '';
    return url.startsWith('mailto:') ? Icons.alternate_email : Icons.link;
  }
  if (source.startsWith('#tylog.tag(')) return Icons.tag;
  if (source.startsWith('#tylog.date-ref(')) return Icons.event_outlined;
  if (source.startsWith('#tylog.attachment(')) return Icons.attach_file;
  if (source.startsWith('#cite(') || source.startsWith('@')) {
    return Icons.format_quote;
  }
  if (source.startsWith('#tylog.ref-note(')) {
    return switch (resolvedKind) {
      'unresolved' => Icons.add_circle_outline,
      'ambiguous' => Icons.error_outline,
      _ => iconForKind(resolvedKind),
    };
  }
  return Icons.link;
}

String? _refNoteKind(String source, String? Function(String id)? resolveKind) {
  if (!source.startsWith('#tylog.ref-note(')) return null;
  final id = RegExp(
    r'^#tylog\.ref-note\("((?:\\.|[^"])*)"',
  ).firstMatch(source)?.group(1);
  return id == null ? null : resolveKind?.call(unescapeTypstString(id));
}

int? _squareEnd(String source, int open) {
  var depth = 0;
  for (var i = open; i < source.length; i++) {
    if (source.codeUnitAt(i) == 92) {
      i++;
      continue;
    }
    if (source.codeUnitAt(i) == 91) depth++;
    if (source.codeUnitAt(i) == 93 && --depth == 0) return i + 1;
  }
  return null;
}

int _unescapedIndexOf(String source, String value, int start) {
  var index = source.indexOf(value, start);
  while (index >= 0 && index > 0 && source.codeUnitAt(index - 1) == 92) {
    index = source.indexOf(value, index + 1);
  }
  return index;
}

/// Exclusive end of a balanced, string-aware `(...)` group starting at
/// [open] (which must be `(`), or null if unbalanced.
int? _parenEnd(String source, int open) {
  var depth = 0;
  var inString = false;
  for (var i = open; i < source.length; i++) {
    final code = source.codeUnitAt(i);
    if (code == 92) {
      i++;
      continue;
    }
    if (code == 34) {
      inString = !inString;
      continue;
    }
    if (inString) continue;
    if (code == 40) depth++;
    if (code == 41 && --depth == 0) return i + 1;
  }
  return null;
}

/// Tries to parse `#highlight[...]` (default fill, stored as `''`) or
/// `#highlight(fill: <expr>)[...]` (verbatim fill expression) starting at
/// [i]. Returns the exclusive end index and the parsed nested parts, or
/// null if the shape doesn't match — in which case the caller falls through
/// to the generic inline-call handling, so a malformed/unsupported
/// `#highlight(...)` becomes a protected atom instead of destroying the
/// whole block.
(int, List<TyLogInline>)? _tryParseHighlight(
  String source,
  int i,
  TyLogInlineStyle inherited,
) {
  const name = '#highlight';
  if (!source.startsWith(name, i)) return null;
  final nameEnd = i + name.length;
  if (nameEnd >= source.length) return null;
  if (source.codeUnitAt(nameEnd) == 91) {
    final close = _squareEnd(source, nameEnd);
    if (close == null) return null;
    final nested = _parseInline(
      source.substring(nameEnd + 1, close - 1),
      inherited: inherited.copyWith(highlight: ''),
    );
    return nested == null ? null : (close, nested);
  }
  if (source.codeUnitAt(nameEnd) != 40) return null;
  final parenClose = _parenEnd(source, nameEnd);
  if (parenClose == null ||
      parenClose >= source.length ||
      source.codeUnitAt(parenClose) != 91) {
    return null;
  }
  final inner = source.substring(nameEnd + 1, parenClose - 1).trim();
  final fillMatch = RegExp(r'^fill:\s*(.*)$').firstMatch(inner);
  if (fillMatch == null) return null;
  final fill = fillMatch.group(1)!.trim();
  final squareClose = _squareEnd(source, parenClose);
  if (squareClose == null) return null;
  final nested = _parseInline(
    source.substring(parenClose + 1, squareClose - 1),
    inherited: inherited.copyWith(highlight: fill),
  );
  return nested == null ? null : (squareClose, nested);
}

void _replaceInBlock(
  TyLogBlock block,
  int start,
  int end,
  String replacement, {
  TyLogInlineStyle? insertionStyle,
}) {
  // Convert only the parts the edit touches (plus the one before it, for the
  // inherited style): exploding a long paragraph into per-character units on
  // every keystroke cost ~25 ms on the A24 (P12).
  final parts = block.parts;
  int partAt(int offset) {
    var at = 0;
    for (var i = 0; i < parts.length; i++) {
      at += parts[i].isAtom ? 1 : parts[i].text.length;
      if (offset < at) return i;
    }
    return parts.length - 1;
  }

  final lo = parts.isEmpty ? 0 : partAt(math.max(0, start - 1));
  // Characters [start, end) are replaced; an insertion only needs part lo.
  final hi = parts.isEmpty ? -1 : (end > start ? partAt(end - 1) : lo);
  var base = 0;
  for (var i = 0; i < lo; i++) {
    base += parts[i].isAtom ? 1 : parts[i].text.length;
  }
  final part = hi == lo ? parts[lo] : null;
  if (part != null &&
      !part.isAtom &&
      (insertionStyle == null || insertionStyle == part.style)) {
    // Typing inside one text run (the common case): splice its string; one
    // run can be a whole long paragraph.
    block
      ..parts = _normalize([
        ...parts.sublist(0, lo),
        TyLogInline.text(
          part.text.replaceRange(start - base, end - base, replacement),
          style: part.style,
        ),
        ...parts.sublist(lo + 1),
      ])
      ..dirty = true;
    return;
  }
  final units = _units(parts.sublist(lo, hi + 1));
  final from = start - base;
  final inherited =
      insertionStyle ??
      (from > 0 && from <= units.length
          ? units[from - 1].style
          : from < units.length
          ? units[from].style
          : const TyLogInlineStyle());
  units.replaceRange(
    from,
    end - base,
    replacement.codeUnits.map((code) => _Unit(code, inherited, null)),
  );
  block
    ..parts = _normalize([
      // _normalize appends into the previous text part: copy the neighbours
      // it may merge into so the undo snapshot's parts stay untouched.
      for (var i = 0; i < lo; i++) i == lo - 1 ? parts[i].copy() : parts[i],
      ..._parts(units),
      for (var i = hi + 1; i < parts.length; i++)
        i == hi + 1 ? parts[i].copy() : parts[i],
    ])
    ..dirty = true;
}

void _styleBlock(
  TyLogBlock block,
  int start,
  int end, {
  bool? bold,
  bool? italic,
  bool? strike,
  bool? underline,
  bool? mono,
  Object? highlight = _unsetHighlight,
  bool reset = false,
}) {
  final units = _units(block.parts);
  for (var i = start; i < end && i < units.length; i++) {
    if (units[i].atom != null) continue;
    final style = reset
        ? const TyLogInlineStyle()
        : units[i].style.copyWith(
            bold: bold,
            italic: italic,
            strike: strike,
            underline: underline,
            mono: mono,
            highlight: highlight,
          );
    units[i] = _Unit(units[i].code, style, null);
  }
  block
    ..parts = _parts(units)
    ..dirty = true;
}

List<_Unit> _units(Iterable<TyLogInline> parts) => [
  for (final part in parts)
    if (part.isAtom)
      _Unit(0xFFFC, part.style, part)
    else
      for (final code in part.text.codeUnits) _Unit(code, part.style, null),
];

List<TyLogInline> _parts(List<_Unit> units) {
  final result = <TyLogInline>[];
  final codes = <int>[];
  TyLogInlineStyle? style;
  void flush() {
    if (codes.isEmpty) {
      return;
    }
    result.add(TyLogInline.text(String.fromCharCodes(codes), style: style!));
    codes.clear();
  }

  for (final unit in units) {
    if (unit.atom != null) {
      flush();
      result.add(unit.atom!.copy());
      style = null;
      continue;
    }
    if (style != null && style != unit.style) flush();
    style = unit.style;
    codes.add(unit.code);
  }
  flush();
  return _normalize(result);
}

List<TyLogInline> _normalize(List<TyLogInline> parts) {
  final result = <TyLogInline>[];
  for (final part in parts) {
    if (!part.isAtom && part.text.isEmpty) continue;
    if (!part.isAtom &&
        result.isNotEmpty &&
        !result.last.isAtom &&
        result.last.style == part.style) {
      result.last.text += part.text;
    } else {
      result.add(part);
    }
  }
  return result;
}

TyLogBlock _newParagraph(String text, int id, {required String separator}) =>
    TyLogBlock(
      id: 'new-$id',
      style: TyLogBlockStyle.paragraph,
      parts: [TyLogInline.text(text)],
      originalSource: '',
      separator: separator,
      dirty: true,
    );

TyLogBlock _blockFrom(
  TyLogBlock original,
  List<_Unit> units, {
  TyLogBlockStyle? style,
  int? headingLevel,
}) => TyLogBlock(
  id: 'split-${DateTime.now().microsecondsSinceEpoch}-${units.hashCode}',
  style: style ?? original.style,
  parts: _parts(units),
  originalSource: '',
  separator: original.separator,
  dirty: true,
  headingLevel: headingLevel ?? original.headingLevel,
);

/// A paragraph line that begins with a Typst block marker (`= ` heading,
/// `- `/`+ ` list, `N. ` enum, or a whole-line `$…$` equation) is a *paragraph*
/// here, not that construct — but serialized verbatim it would re-parse as the
/// other kind, so `toSource` validation fails and the edit silently reverts
/// (the "can't press Enter / paste a list" bug). Escaping the first char keeps
/// the visible text identical (`_parseInline` unescapes any `\x`) while making
/// the line parse — and Typst-render — as literal prose.
/// A Typst list marker at the start of a line: indent, then `-`/`+`/`N.`,
/// then whitespace *or* end-of-line. Requiring the separator is what keeps
/// `-foo` (not a list item) and `1.5` out, while still matching a marker with
/// no content after it — the empty trailing bullet every Logseq page carries.
final _listMarker = RegExp(r'^([ \t]*)(?:([-+])|(\d+)\.)(?:[ \t]+|$)');

/// The inverse of [_listMarker]: a rendered glyph back to its source marker.
/// A line with no glyph is a continuation line and is returned untouched, so
/// glyph presence and marker presence stay one-to-one across the round trip.
String _serializeListLine(String line) {
  final glyph = RegExp(r'^([ \t]*)(?:(•)|(\d+)\.)[ \t]*').firstMatch(line);
  if (glyph == null) return line;
  return '${glyph.group(1)}${glyph.group(2) != null ? '- ' : '+ '}'
      '${line.substring(glyph.end)}';
}

/// Indented markers count too: block classification skips leading whitespace,
/// so `  - x` re-parses as a list just as `- x` does.
final _leadingBlockMarker = RegExp(r'^([ \t]*)(?:=+ |[-+] |\d+\. )');
final _leadingEquation = RegExp(r'^([ \t]*)\$.*\$$');
String _escapeParagraphMarkers(String content) => content
    .split('\n')
    .map((line) {
      final marker =
          _leadingBlockMarker.firstMatch(line) ??
          _leadingEquation.firstMatch(line);
      // The escape goes *after* the indent — a leading `\ ` is a non-breaking
      // space in Typst, not an escaped marker.
      return marker == null
          ? line
          : '${marker[1]}\\${line.substring(marker[1]!.length)}';
    })
    .join('\n');

String _serializeBlock(TyLogBlock block) {
  if (block.isProtected) return block.originalSource;
  final content = block.parts.map(_serializePart).join();
  return switch (block.style) {
    TyLogBlockStyle.heading => '${'=' * block.headingLevel} $content',
    // One mapper for both list styles: the *glyph* decides the marker, not the
    // block's style, so a `+` item inside a mostly-`-` block survives instead
    // of being rewritten as a bullet.
    TyLogBlockStyle.bulletList || TyLogBlockStyle.numberedList =>
      content.split('\n').map(_serializeListLine).join('\n'),
    TyLogBlockStyle.paragraph => _escapeParagraphMarkers(content),
    TyLogBlockStyle.protected => block.originalSource,
    TyLogBlockStyle.taskLine => replaceTaskText(
      block.originalSource,
      taskField(block.originalSource, 'id')!,
      block.visibleText.replaceFirst(
        RegExp(
          '^[$taskUncheckedGlyph$taskDoingGlyph$taskCheckedGlyph$taskCancelledGlyph] ',
        ),
        '',
      ),
    ),
  };
}

/// Nesting order is innermost → outermost: raw backticks (mono) first —
/// Typst raw content can't contain other markup, so it must sit closest to
/// the text — then #emph/#strong/#strike/#underline, with #highlight
/// outermost since markup nests validly inside a highlighted region.
///
/// Known limitation: mono text containing a literal backtick cannot
/// round-trip (there is no escape for it in single-backtick raw); `toSource`
/// validation reverts the edit rather than emit broken Typst.
String _serializePart(TyLogInline part) {
  if (part.isAtom) return part.source!;
  var value = part.style.mono ? '`${part.text}`' : escapeMarkup(part.text);
  if (part.style.italic) value = '#emph[$value]';
  if (part.style.bold) value = '#strong[$value]';
  if (part.style.strike) value = '#strike[$value]';
  if (part.style.underline) value = '#underline[$value]';
  final highlight = part.style.highlight;
  if (highlight != null) {
    value = highlight.isEmpty
        ? '#highlight[$value]'
        : '#highlight(fill: $highlight)[$value]';
  }
  return value;
}

/// The round-trip validation failure — the one FormatException the commit path
/// treats as a benign normalization candidate for accept-and-resync (all other
/// guards, e.g. task integrity / protected crossing, must revert).
const _validateFailMessage = 'Rich editor could not validate Typst output.';

/// Normalizes away the newline differences a Typst round-trip is allowed to
/// introduce: a run of 3+ newlines collapses to the `\n\n` block separator, and
/// trailing newlines are dropped. Single (intra-paragraph) and double
/// (block-separator) newlines are preserved, so this treats block-structure
/// whitespace as benign while still catching any real content change.
String _canonicalNewlines(String s) =>
    s.replaceAll(RegExp(r'\n{3,}'), '\n\n').replaceFirst(RegExp(r'\n+$'), '');

bool _sameProtectedSources(TyLogDocument a, TyLogDocument b) {
  final aSources = [
    for (final block in a.blocks)
      if (block.isProtected) block.originalSource,
    for (final block in a.blocks)
      for (final part in block.parts)
        if (part.isAtom) part.source,
  ];
  final bSources = [
    for (final block in b.blocks)
      if (block.isProtected) block.originalSource,
    for (final block in b.blocks)
      for (final part in block.parts)
        if (part.isAtom) part.source,
  ];
  return aSources.length == bSources.length &&
      List.generate(
        aSources.length,
        (i) => aSources[i] == bSources[i],
      ).every((same) => same);
}

_Replacement _replacement(String oldText, String newText) {
  var start = 0;
  while (start < oldText.length &&
      start < newText.length &&
      oldText.codeUnitAt(start) == newText.codeUnitAt(start)) {
    start++;
  }
  var oldEnd = oldText.length;
  var newEnd = newText.length;
  while (oldEnd > start &&
      newEnd > start &&
      oldText.codeUnitAt(oldEnd - 1) == newText.codeUnitAt(newEnd - 1)) {
    oldEnd--;
    newEnd--;
  }
  return _Replacement(start, oldEnd, newText.substring(start, newEnd));
}

/// [root]'s flat children cut to text offsets [from, to); a WidgetSpan
/// (chip) counts as one character, as in `visibleText`.
TextSpan _sliceSpan(TextSpan root, int from, int to) {
  final out = <InlineSpan>[];
  var pos = 0;
  for (final child in root.children ?? const <InlineSpan>[]) {
    if (pos >= to) break;
    if (child is TextSpan) {
      final text = child.text ?? '';
      final a = math.max(from, pos);
      final b = math.min(to, pos + text.length);
      if (a < b) {
        out.add(
          a == pos && b == pos + text.length
              ? child
              : TextSpan(
                  text: text.substring(a - pos, b - pos),
                  style: child.style,
                  recognizer: child.recognizer,
                ),
        );
      }
      pos += text.length;
    } else {
      if (pos >= from) out.add(child);
      pos += 1;
    }
  }
  return TextSpan(style: root.style, children: out);
}

void _addTextSpans(
  List<InlineSpan> target,
  String text,
  int global, {
  required TextStyle style,
  required TextRange composing,
}) {
  final start = math.max(global, composing.start);
  final end = math.min(global + text.length, composing.end);
  if (!composing.isValid || start >= end) {
    target.add(TextSpan(text: text, style: style));
    return;
  }
  if (start > global) {
    target.add(TextSpan(text: text.substring(0, start - global), style: style));
  }
  target.add(
    TextSpan(
      text: text.substring(start - global, end - global),
      style: style.copyWith(decoration: TextDecoration.underline),
    ),
  );
  if (end < global + text.length) {
    target.add(TextSpan(text: text.substring(end - global), style: style));
  }
}

TextStyle _styleFor(
  BuildContext context,
  TextStyle? base,
  TyLogBlockStyle block,
  int headingLevel,
  TyLogInlineStyle inline,
) {
  var style = base ?? DefaultTextStyle.of(context).style;
  if (block == TyLogBlockStyle.heading) {
    final textTheme = Theme.of(context).textTheme;
    final headingStyle = switch (headingLevel) {
      1 => textTheme.headlineSmall,
      2 => textTheme.titleLarge,
      3 => textTheme.titleMedium,
      _ => textTheme.titleSmall,
    };
    style = style.merge(headingStyle);
  }
  if (block == TyLogBlockStyle.bulletList) {
    style = style.copyWith(fontFeatures: const [FontFeature.tabularFigures()]);
  }
  final decorations = <TextDecoration>[
    if (inline.strike) TextDecoration.lineThrough,
    if (inline.underline) TextDecoration.underline,
  ];
  return style.copyWith(
    fontWeight: inline.bold ? FontWeight.bold : style.fontWeight,
    fontStyle: inline.italic ? FontStyle.italic : style.fontStyle,
    decoration: decorations.isEmpty
        ? style.decoration
        : TextDecoration.combine(decorations),
    fontFamily: inline.mono ? 'monospace' : style.fontFamily,
    fontSize: inline.mono && style.fontSize != null
        ? style.fontSize! * 0.9
        : style.fontSize,
    backgroundColor: inline.highlight != null
        ? _highlightColor(inline.highlight!, Theme.of(context).brightness)
        : style.backgroundColor,
  );
}

/// Line starts every [linesPerChunk] lines in [from, to): the static text
/// around the editing window is split so each chunk is laid out once.
List<int> _chunkStarts(
  String text,
  int from,
  int to, {
  int linesPerChunk = 20,
}) {
  if (from >= to) return const [];
  final starts = [from];
  var lines = 0;
  for (var i = from; i < to - 1; i++) {
    if (text.codeUnitAt(i) == 0x0A && ++lines == linesPerChunk) {
      starts.add(i + 1);
      lines = 0;
    }
  }
  return starts;
}

/// Static text outside the editing window; a tap places the caret at the
/// tapped character.
class _StaticChunk extends StatefulWidget {
  const _StaticChunk({
    required this.span,
    required this.strutStyle,
    required this.onTapOffset,
  });

  final TextSpan span;
  final StrutStyle? strutStyle;
  final ValueChanged<int> onTapOffset;

  @override
  State<_StaticChunk> createState() => _StaticChunkState();
}

class _StaticChunkState extends State<_StaticChunk> {
  final _key = GlobalKey();

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTapUp: (details) {
      final paragraph = _key.currentContext?.findRenderObject();
      if (paragraph is! RenderParagraph) return;
      widget.onTapOffset(
        paragraph
            .getPositionForOffset(
              paragraph.globalToLocal(details.globalPosition),
            )
            .offset,
      );
    },
    child: RichText(
      key: _key,
      text: widget.span,
      strutStyle: widget.strutStyle,
    ),
  );
}

bool _taskHasStrip(TyLogBlock block) {
  if (block.style != TyLogBlockStyle.taskLine) return false;
  final source = block.originalSource;
  final priority = taskField(source, 'priority') ?? 'normal';
  return priority != 'normal' ||
      taskField(source, 'due') != null ||
      taskField(source, 'scheduled') != null ||
      taskField(source, 'recurrence') != null ||
      taskClocked(source, taskField(source, 'id')!).isNotEmpty;
}

/// Paint after EditableText, using its actual wrapping and scroll geometry.
class _TaskStripFlow extends FlowDelegate {
  _TaskStripFlow({
    required this.controller,
    required this.window,
    required this.editable,
    required this.origin,
    required super.repaint,
  });
  final TyLogEditingController controller;
  final TyLogWindowController? window;
  final RenderEditable? Function() editable;
  final RenderBox? Function() origin;

  @override
  BoxConstraints getConstraintsForChild(int i, BoxConstraints constraints) =>
      BoxConstraints(
        maxWidth: math.min(360, math.max(0, constraints.maxWidth - 36)),
      );

  @override
  void paintChildren(FlowPaintingContext context) {
    final field = editable();
    final box = origin();
    if (field == null || box == null || !field.hasSize) return;
    var child = 0;
    for (final range in controller.document._ranges) {
      if (!_taskHasStrip(controller.document.blocks[range.index])) continue;
      final offset = range.end - (window?.start ?? 0);
      if (offset < 0 || offset > field.plainText.length) {
        child++;
        continue;
      }
      final caret = field.getLocalRectForCaret(TextPosition(offset: offset));
      final point = box.globalToLocal(field.localToGlobal(caret.bottomLeft));
      final size = context.getChildSize(child)!;
      final block = controller.document.blocks[range.index];
      final beside = point.dx + 8 + size.width <= context.size.width - 18;
      final reservedHeight = beside ? 0.0 : size.height + 2;
      if (controller.taskStripHeights[block.id] != reservedHeight) {
        controller.taskStripHeights[block.id] = reservedHeight;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (box.attached) controller.refreshTaskStripLayout();
        });
      }
      final current = child++;
      if (point.dy <= 0 || point.dy - caret.height >= context.size.height) {
        continue;
      }
      context.paintChild(
        current,
        transform: Matrix4.translationValues(
          beside ? point.dx + 8 : 18,
          beside ? point.dy - caret.height : point.dy + 2,
          0,
        ),
      );
    }
  }

  @override
  bool shouldRepaint(_TaskStripFlow oldDelegate) => true;
}
