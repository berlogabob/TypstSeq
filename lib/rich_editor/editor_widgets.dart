part of '../rich_editor.dart';

class TyLogRichEditor extends StatefulWidget {
  const TyLogRichEditor({
    super.key,
    required this.controller,
    required this.onInsert,
    this.onMentionQuery,
    this.onCommandSelected,
  });

  final TyLogEditingController controller;
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

  @override
  State<TyLogRichEditor> createState() => _TyLogRichEditorState();
}

class TyLogReadView extends StatefulWidget {
  const TyLogReadView({
    super.key,
    required this.source,
    this.imageResolver,
    this.resolveKind,
  });

  final String source;
  final Future<Uint8List?> Function(String path)? imageResolver;
  final String? Function(String target)? resolveKind;

  @override
  State<TyLogReadView> createState() => _TyLogReadViewState();
}

class _TyLogReadViewState extends State<TyLogReadView> {
  late final TyLogEditingController controller = TyLogEditingController(
    source: widget.source,
    onSourceChanged: (_) {},
    onError: (_) {},
    onProtectedTap: (_) {},
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
  Widget build(BuildContext context) => SelectableText.rich(
    controller.readTextSpan(
      context,
      style: Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.55),
    ),
  );
}

const _defaultAutocompleteDebounce = Duration(milliseconds: 150);
const _autocompleteRowHeight = 48.0;
const _autocompleteMaxVisible = 6;

class _TyLogRichEditorState extends State<TyLogRichEditor> {
  late final FocusNode focusNode;
  final LayerLink _layerLink = LayerLink();
  final ValueNotifier<_AutocompleteState?> _autocomplete = ValueNotifier(null);
  OverlayEntry? _overlayEntry;
  Timer? _debounce;
  int _mentionQueryToken = 0;
  final GlobalKey _headingButtonKey = GlobalKey();
  final GlobalKey _highlightButtonKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    focusNode = FocusNode(onKeyEvent: _handleKey);
    focusNode.addListener(_focusChanged);
    if (kEnableInlineAutocomplete) {
      widget.controller.addListener(_handleControllerChanged);
    }
  }

  void _focusChanged() {
    if (!focusNode.hasFocus) _cancelAutocomplete();
    setState(() {});
  }

  KeyEventResult _handleKey(FocusNode _, KeyEvent event) {
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
    if (trigger.kind == AutocompleteTriggerKind.command) {
      _debounce?.cancel();
      _autocomplete.value = _AutocompleteState(
        trigger: trigger,
        mentionItems: const [],
        commandItems: _filterCommands(trigger.query),
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
    final normalized = query.toLowerCase();
    return actions
        .where(
          (action) => (kMagicActionDisplay[action]?.$2 ?? action.name)
              .toLowerCase()
              .contains(normalized),
        )
        .toList();
  }

  Future<void> _runMentionQuery(AutocompleteTrigger trigger) async {
    final onMentionQuery = widget.onMentionQuery;
    if (onMentionQuery == null) return;
    final token = ++_mentionQueryToken;
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
      mentionItems: results,
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
        : state.commandItems.length;
    if (count == 0) return;
    final next = (state.highlighted + delta) % count;
    _autocomplete.value = state.copyWith(
      highlighted: next < 0 ? next + count : next,
    );
  }

  void _activateHighlighted() {
    final state = _autocomplete.value;
    if (state == null) return;
    if (_isMentionLike(state.trigger.kind)) {
      if (state.highlighted < state.mentionItems.length) {
        _selectMention(state.mentionItems[state.highlighted]);
      }
    } else {
      if (state.highlighted < state.commandItems.length) {
        _selectCommand(state.commandItems[state.highlighted]);
      }
    }
  }

  // Wiki-links (`[[`) share the mention popup, query, and state machine.
  static bool _isMentionLike(AutocompleteTriggerKind kind) =>
      kind == AutocompleteTriggerKind.mention ||
      kind == AutocompleteTriggerKind.wikiLink;

  void _selectMention(MentionSuggestion item) {
    final trigger = _autocomplete.value?.trigger;
    if (trigger == null) return;
    final caret = widget.controller.selection.baseOffset;
    _cancelAutocomplete();
    // Drop the "@query" / "[[query" text and insert on a collapsed caret so the
    // snippet body comes from the chosen title, not the raw typed query (which
    // would otherwise embed a literal "[[..." for a note link).
    widget.controller.value = widget.controller.value.copyWith(
      text: widget.controller.text.replaceRange(trigger.start, caret, ''),
      selection: TextSelection.collapsed(offset: trigger.start),
      composing: TextRange.empty,
    );
    // `@` keeps its "@name" mention rendering; `[[` writes a plain note
    // reference or a tag, so a wiki-link never leaves the "@" prefix behind.
    final request = switch (item.kind) {
      MentionKind.concept => MagicRequest(
        action: MagicAction.tag,
        value: item.id,
      ),
      MentionKind.note =>
        trigger.kind == AutocompleteTriggerKind.wikiLink
            ? MagicRequest(
                action: MagicAction.noteLink,
                id: item.id,
                value: item.title,
              )
            : MagicRequest(
                action: MagicAction.mention,
                id: item.id,
                value: item.title,
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

  void _cancelAutocomplete() {
    _debounce?.cancel();
    _debounce = null;
    _mentionQueryToken++;
    if (_autocomplete.value != null) _autocomplete.value = null;
    _removeOverlay();
  }

  void _ensureOverlay() {
    if (_overlayEntry != null) return;
    final overlay = Overlay.maybeOf(context);
    if (overlay == null) return;
    _overlayEntry = OverlayEntry(builder: _buildOverlayContent);
    overlay.insert(_overlayEntry!);
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  Widget _buildOverlayContent(BuildContext context) => Positioned(
    width: 320,
    child: CompositedTransformFollower(
      link: _layerLink,
      showWhenUnlinked: false,
      targetAnchor: Alignment.topLeft,
      followerAnchor: Alignment.topLeft,
      offset: const Offset(16, 44),
      child: TextFieldTapRegion(
        child: ValueListenableBuilder<_AutocompleteState?>(
          valueListenable: _autocomplete,
          builder: (context, state, _) {
            if (state == null) return const SizedBox.shrink();
            return Material(
              elevation: 6,
              borderRadius: BorderRadius.circular(10),
              clipBehavior: Clip.antiAlias,
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxHeight: _autocompleteRowHeight * _autocompleteMaxVisible,
                ),
                child: _isMentionLike(state.trigger.kind)
                    ? _mentionList(state)
                    : _commandList(state),
              ),
            );
          },
        ),
      ),
    ),
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
      shrinkWrap: true,
      itemCount: state.mentionItems.length,
      itemBuilder: (context, index) {
        final item = state.mentionItems[index];
        return ListTile(
          key: Key('autocomplete-mention-${item.id}'),
          dense: true,
          tileColor: index == state.highlighted
              ? Theme.of(context).colorScheme.surfaceContainerHighest
              : null,
          leading: Icon(
            item.kind == MentionKind.concept
                ? Icons.tag
                : Icons.alternate_email,
          ),
          title: Text(item.title),
          subtitle: Text(item.id),
          onTap: () => _selectMention(item),
        );
      },
    );
  }

  Widget _commandList(_AutocompleteState state) {
    if (state.commandItems.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text('No matching commands'),
      );
    }
    return ListView.builder(
      key: const Key('autocomplete-command-list'),
      shrinkWrap: true,
      itemCount: state.commandItems.length,
      itemBuilder: (context, index) {
        final action = state.commandItems[index];
        final display = kMagicActionDisplay[action];
        return ListTile(
          key: Key('autocomplete-command-${action.name}'),
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
  void dispose() {
    _debounce?.cancel();
    _removeOverlay();
    if (kEnableInlineAutocomplete) {
      widget.controller.removeListener(_handleControllerChanged);
    }
    focusNode.removeListener(_focusChanged);
    focusNode.dispose();
    super.dispose();
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

  Future<void> _showHighlightMenu(BuildContext context) async {
    final fill = await showMenu<String>(
      context: context,
      position: _menuPositionBelow(context, _highlightButtonKey),
      items: const [
        PopupMenuItem(value: kHighlightYellow, child: Text('Yellow')),
        PopupMenuItem(value: kHighlightGreen, child: Text('Green')),
        PopupMenuItem(value: kHighlightPink, child: Text('Pink')),
        PopupMenuItem(value: kHighlightBlue, child: Text('Blue')),
      ],
    );
    if (fill != null) widget.controller.setHighlight(fill);
    if (mounted) focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Expanded(
        child: CompositedTransformTarget(
          link: _layerLink,
          child: TextField(
            key: const Key('rich-journal-editor'),
            controller: widget.controller,
            focusNode: focusNode,
            expands: true,
            minLines: null,
            maxLines: null,
            textAlignVertical: TextAlignVertical.top,
            style: Theme.of(
              context,
            ).textTheme.bodyLarge?.copyWith(height: 1.55),
            decoration: const InputDecoration(
              hintText: 'Start writing…',
              contentPadding: EdgeInsets.all(18),
            ),
            onTap: () => widget.controller.handleEditorTap(),
            onTapOutside: (_) => focusNode.unfocus(),
            contextMenuBuilder: (context, state) => TextFieldTapRegion(
              child: AdaptiveTextSelectionToolbar.buttonItems(
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
                      state.selectAll(SelectionChangedCause.toolbar);
                    },
                  ),
                ],
              ),
            ),
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
                      tooltip: 'Heading 1 (long-press for more levels)',
                      onPressed: widget.controller.setHeading,
                      onLongPress: () => _showHeadingMenu(context),
                      icon: Text(
                        'H1',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
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

/// Renders an image atom (`#image(...)`) as a real inline picture, loaded from
/// the vault via the controller's cached [bytes] future. While loading it shows
/// a compact placeholder; on a missing file / decode error it falls back to
/// [fallback] (the original path chip) so a dead reference is still visible.
class _InlineImage extends StatelessWidget {
  const _InlineImage({
    required this.bytes,
    required this.fallback,
    required this.onTap,
  });

  final Future<Uint8List?> bytes;
  final Widget fallback;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => FutureBuilder<Uint8List?>(
    future: bytes,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: SizedBox(
            height: 18,
            width: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        );
      }
      final data = snapshot.data;
      if (data == null || data.isEmpty) return fallback;
      final image = ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.7,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.memory(
            data,
            fit: BoxFit.contain,
            errorBuilder: (context, _, _) => fallback,
          ),
        ),
      );
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: onTap == null
            ? image
            : GestureDetector(onTap: onTap, child: image),
      );
    },
  );
}

class _ProtectedChip extends StatelessWidget {
  const _ProtectedChip({
    required this.label,
    required this.block,
    required this.onTap,
    required this.icon,
  });

  final String label;
  final bool block;
  final VoidCallback? onTap;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Semantics(
    button: onTap != null,
    label: '$label, protected Typst',
    child: Padding(
      padding: EdgeInsets.symmetric(horizontal: block ? 0 : 2, vertical: 2),
      child: Material(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: block ? 12 : 7,
              vertical: block ? 10 : 3,
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
                // Inline chips are one line — center the icon with the text so
                // it doesn't float above the baseline. Block chips can wrap to
                // several lines, so keep their icon aligned to the first line.
                crossAxisAlignment: block
                    ? CrossAxisAlignment.start
                    : CrossAxisAlignment.center,
                children: [
                  Icon(icon, size: 16),
                  const SizedBox(width: 5),
                  Flexible(child: Text(label)),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

TyLogBlock _parseBlock(ControlledBlock block, String separator, int index) {
  final source = block.source;
  final trimmed = source.trimLeft();
  final id = 'block-$index-${source.hashCode}';
  if (block.kind == ControlledBlockKind.task) {
    final taskId = taskField(source, 'id');
    final taskText = taskField(source, 'text');
    if (taskId != null && taskText != null) {
      final glyph = taskField(source, 'status') == 'done'
          ? taskCheckedGlyph
          : taskUncheckedGlyph;
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
    final numbered = RegExp(r'^(?:\d+\. |\+ )').hasMatch(trimmed);
    style = numbered
        ? TyLogBlockStyle.numberedList
        : TyLogBlockStyle.bulletList;
    var number = 1;
    body = trimmed
        .split('\n')
        .map((line) {
          final content = line.replaceFirst(RegExp(r'^(?:[-+] |\d+\. )'), '');
          return numbered ? '${number++}. $content' : '• $content';
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

    final atomMatch = RegExp(
      r'^(#(?:link|tylog\.(?:ref-note|date-ref|attachment))\([^\n]*?\)\[[^\]]*\]|#tylog\.tag\("(?:\\.|[^"])*"\)|#cite\([^)]*\)|#[iI]mage\([^)]*\)|@[A-Za-z0-9_.:+-]+)',
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

/// The vault asset path an atom points at when it is an image — a bare
/// `#image("path")` or a `#tylog.attachment("path", kind: "image")[...]` — else
/// null. Used to draw the atom as a real picture instead of a link chip.
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

String _atomLabel(String source) {
  final content = RegExp(r'\[([^\]]*)\]$').firstMatch(source)?.group(1);
  if (content != null && content.isNotEmpty) {
    return content.replaceAll(r'\@', '@');
  }
  final quoted = RegExp(r'"((?:\\.|[^"])*)"').firstMatch(source)?.group(1);
  if (quoted != null) {
    return quoted.replaceAll(r'\"', '"').replaceAll(r'\\', r'\');
  }
  if (source.startsWith('@')) return source.substring(1);
  if (source.startsWith('#cite(')) {
    return source.substring(6, source.length - 1);
  }
  return source.startsWith('#image') ? 'Image' : 'Reference';
}

/// The chip icon for an inline atom, by what it points at: email vs web link,
/// tag, date, attachment, citation, and — via [resolveKind] against the vault
/// index — the referenced note's kind (person/place/project/…).
IconData _atomIcon(String source, {String? Function(String id)? resolveKind}) {
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
    final id = RegExp(
      r'^#tylog\.ref-note\("((?:\\.|[^"])*)"',
    ).firstMatch(source)?.group(1);
    return iconForKind(
      id == null ? null : resolveKind?.call(unescapeTypstString(id)),
    );
  }
  return Icons.link;
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
  final units = _units(block.parts);
  final inherited =
      insertionStyle ??
      (start > 0 && start <= units.length
          ? units[start - 1].style
          : start < units.length
          ? units[start].style
          : const TyLogInlineStyle());
  units.replaceRange(
    start,
    end,
    replacement.codeUnits.map((code) => _Unit(code, inherited, null)),
  );
  block
    ..parts = _parts(units)
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
final _leadingBlockMarker = RegExp(r'^(?:=+ |[-+] |\d+\. )');
String _escapeParagraphMarkers(String content) => content
    .split('\n')
    .map(
      (line) =>
          _leadingBlockMarker.hasMatch(line) ||
              (line.length >= 2 && line.startsWith(r'$') && line.endsWith(r'$'))
          ? '\\$line'
          : line,
    )
    .join('\n');

String _serializeBlock(TyLogBlock block) {
  if (block.isProtected) return block.originalSource;
  final content = block.parts.map(_serializePart).join();
  return switch (block.style) {
    TyLogBlockStyle.heading => '${'=' * block.headingLevel} $content',
    TyLogBlockStyle.bulletList =>
      content
          .split('\n')
          .map((line) => '- ${line.replaceFirst(RegExp(r'^•\s*'), '')}')
          .join('\n'),
    TyLogBlockStyle.numberedList =>
      content
          .split('\n')
          .map((line) => '+ ${line.replaceFirst(RegExp(r'^\d+\.\s*'), '')}')
          .join('\n'),
    TyLogBlockStyle.paragraph => _escapeParagraphMarkers(content),
    TyLogBlockStyle.protected => block.originalSource,
    TyLogBlockStyle.taskLine => replaceTaskText(
      block.originalSource,
      taskField(block.originalSource, 'id')!,
      block.visibleText.replaceFirst(
        RegExp('^[$taskUncheckedGlyph$taskCheckedGlyph] '),
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
  var value = part.style.mono ? '`${part.text}`' : typstContent(part.text);
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
String _canonicalNewlines(String s) => s
    .replaceAll(RegExp(r'\n{3,}'), '\n\n')
    .replaceFirst(RegExp(r'\n+$'), '');

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
