import 'dart:async';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tylog_core/tylog_core.dart';

import 'constants.dart';
import 'note_picker_sheet.dart';

class BoardsTab extends StatefulWidget {
  const BoardsTab({
    super.key,
    required this.storage,
    required this.index,
    this.imageResolver,
    this.onOpenPath,
  });
  final VaultStorage storage;
  final VaultIndex? index;
  final Future<Uint8List?> Function(String)? imageResolver;
  final ValueChanged<String>? onOpenPath;
  @override
  State<BoardsTab> createState() => _BoardsTabState();
}

class _BoardsTabState extends State<BoardsTab> {
  late Future<List<Board>> boards = load();
  Future<List<Board>> load() async {
    final entries = await widget.storage.list(path: 'boards');
    final result = <Board>[];
    for (final entry in entries) {
      if (!entry.isDirectory && entry.path.endsWith('.board.json')) {
        try {
          result.add(parseBoard(await widget.storage.readText(entry.path)));
        } catch (_) {
          /* Keep other boards accessible. */
        }
      }
    }
    return result..sort((a, b) => a.title.compareTo(b.title));
  }

  Future<void> open(Board board, {bool create = false}) async {
    if (create) await writeBoard(widget.storage, board);
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => Whiteboard(
          board: board,
          storage: widget.storage,
          index: widget.index,
          imageResolver: widget.imageResolver,
          onOpenPath: widget.onOpenPath,
        ),
      ),
    );
    if (mounted) setState(() => boards = load());
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Align(
        alignment: Alignment.centerRight,
        child: TextButton.icon(
          onPressed: () {
            final id = 'wb-${DateTime.now().microsecondsSinceEpoch}';
            open(
              Board(id: id, title: 'Whiteboard', layout: 'free'),
              create: true,
            );
          },
          icon: const Icon(Icons.add),
          label: const Text('New whiteboard'),
        ),
      ),
      Expanded(
        child: FutureBuilder<List<Board>>(
          future: boards,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Text('Could not load boards: ${snapshot.error}');
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            return ListView(
              children: [
                for (final board in snapshot.data!)
                  ListTile(
                    title: Text(board.title),
                    subtitle: Text(
                      '${board.layout} · ${board.cards.length} cards',
                    ),
                    onTap: () => open(board),
                  ),
              ],
            );
          },
        ),
      ),
    ],
  );
}

Future<void> openEntityWhiteboard(
  BuildContext context, {
  required VaultStorage storage,
  required VaultIndex? index,
  required String entityId,
  required String title,
  Future<Uint8List?> Function(String)? imageResolver,
  ValueChanged<String>? onOpenPath,
}) async {
  final id = '$entityId-wb';
  var board = await readBoard(storage, id);
  if (board == null) {
    board = Board(id: id, title: title, layout: 'free', scopeEntity: entityId);
    await writeBoard(storage, board);
  }
  if (!context.mounted) return;
  await Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => Whiteboard(
        board: board!,
        storage: storage,
        index: index,
        imageResolver: imageResolver,
        onOpenPath: onOpenPath,
      ),
    ),
  );
}

class Whiteboard extends StatefulWidget {
  const Whiteboard({
    super.key,
    required this.board,
    required this.storage,
    required this.index,
    this.imageResolver,
    this.onOpenPath,
  });
  final Board board;
  final VaultStorage storage;
  final VaultIndex? index;
  final Future<Uint8List?> Function(String)? imageResolver;
  final ValueChanged<String>? onOpenPath;
  @override
  State<Whiteboard> createState() => _WhiteboardState();
}

class _WhiteboardState extends State<Whiteboard> {
  static const origin = 50000.0;
  late Board board = widget.board;
  late final TransformationController transform;
  Timer? timer;
  Future<void> writes = Future.value();
  String? selected;
  String? selectedEdge;
  bool connecting = false;
  final viewerKey = GlobalKey();
  Offset dragPosition = Offset.zero;
  Size size = Size.zero;
  @override
  void initState() {
    super.initState();
    final v = board.viewport;
    transform = TransformationController(
      Matrix4.identity()
        ..translateByDouble(
          v.x.toDouble() - origin * v.zoom,
          v.y.toDouble() - origin * v.zoom,
          0,
          1,
        )
        ..scaleByDouble(v.zoom.toDouble(), v.zoom.toDouble(), 1, 1),
    );
    transform.addListener(viewportChanged);
  }

  void viewportChanged() {
    final m = transform.value;
    final v = BoardViewport(
      x: m.storage[12] + origin * m.getMaxScaleOnAxis(),
      y: m.storage[13] + origin * m.getMaxScaleOnAxis(),
      zoom: m.getMaxScaleOnAxis(),
      extra: board.viewport.extra,
    );
    board = Board.fromJson({...board.toJson(), 'viewport': v.toJson()});
    if (mounted) setState(() {});
    scheduleSave();
  }

  void scheduleSave() {
    timer?.cancel();
    timer = Timer(const Duration(milliseconds: 500), save);
  }

  void save() {
    timer?.cancel();
    timer = null;
    final snapshot = board;
    writes = writes
        .then((_) => writeBoard(widget.storage, snapshot))
        .catchError((Object e) {
          if (mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text('Could not save board: $e')));
          }
        });
  }

  @override
  void dispose() {
    if (timer != null) save();
    transform.removeListener(viewportChanged);
    transform.dispose();
    super.dispose();
  }

  void delete() {
    if (selected == null && selectedEdge == null) return;
    setState(() {
      if (selected != null) board = board.removeCard(selected!);
      if (selectedEdge != null) {
        board = Board.fromJson({
          ...board.toJson(),
          'edges': [
            for (final edge in board.edges)
              if (edge.id != selectedEdge) edge.toJson(),
          ],
        });
      }
      selected = null;
      selectedEdge = null;
    });
    scheduleSave();
  }

  String newId() => DateTime.now().microsecondsSinceEpoch.toString();

  Offset get centre =>
      transform.toScene(Offset(size.width / 2, size.height / 2)) -
      const Offset(origin, origin);

  void addCard(String type, {String? ref, String? text}) {
    final point = centre;
    setState(
      () => board = board.addCard(
        BoardCard(
          id: newId(),
          type: type,
          ref: ref,
          text: text,
          x: point.dx - 120,
          y: point.dy - 60,
        ),
      ),
    );
    scheduleSave();
  }

  Future<String?> prompt(String title, {String initial = ''}) async {
    var value = initial;
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextFormField(
          initialValue: initial,
          onChanged: (text) => value = text,
          autofocus: true,
          maxLines: title == 'Text' ? 5 : 1,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, value),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    return result;
  }

  Future<void> add(String type) async {
    try {
      if (type == 'Note/entity') {
        final note = await showModalBottomSheet<Object>(
          context: context,
          isScrollControlled: true,
          builder: (_) => NotePickerSheet(notes: widget.index?.notes ?? []),
        );
        if (note is NoteRef && mounted) {
          addCard(note.kind == 'note' ? 'note' : 'entity', ref: note.id);
        }
      } else if (type == 'Task') {
        final task = await showModalBottomSheet<TaskRef>(
          context: context,
          builder: (context) => ListView(
            shrinkWrap: true,
            children: [
              for (final task in widget.index?.tasks ?? <TaskRef>[])
                ListTile(
                  title: Text(task.text),
                  onTap: () => Navigator.pop(context, task),
                ),
            ],
          ),
        );
        if (task != null && mounted) addCard('task', ref: task.id);
      } else if (type == 'Text') {
        final value = await prompt('Text');
        if (value != null && mounted) addCard('text', text: value);
      } else if (type == 'Link') {
        final value = await prompt('Link');
        if (value != null && mounted && validUrl(value.trim())) {
          addCard('url', ref: value.trim());
        }
      } else if (type == 'Image from file') {
        final result = await FilePicker.pickFiles(type: FileType.image);
        if (result == null) return;
        final file = result.files.single;
        final bytes = await file.readAsBytes();
        final ext = file.extension?.toLowerCase();
        if (ext == null || !RegExp(r'^[a-z0-9]+$').hasMatch(ext)) {
          return;
        }
        final path =
            'assets/boards/${board.id}/${sha256.convert(bytes).toString().substring(0, 8)}.$ext';
        await widget.storage.createDirectory('assets/boards/${board.id}');
        await widget.storage.writeBytes(path, bytes);
        if (mounted) addCard('asset', ref: path);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not add card: $e')));
      }
    }
  }

  bool validUrl(String value) {
    final uri = Uri.tryParse(value);
    return uri != null &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host.isNotEmpty;
  }

  Future<void> paste() async {
    final value = (await Clipboard.getData(Clipboard.kTextPlain))?.text;
    if (!mounted || value == null || value.isEmpty) return;
    if (validUrl(value.trim())) {
      addCard('url', ref: value.trim());
    } else {
      addCard('text', text: value);
    }
  }

  Future<void> openCard(BoardCard card) async {
    if (card.type == 'text') {
      final value = await prompt('Text', initial: card.text ?? '');
      if (value != null && mounted) {
        setState(
          () => board = Board.fromJson({
            ...board.toJson(),
            'cards': [
              for (final c in board.cards)
                if (c.id == card.id)
                  {...c.toJson(), 'text': value}
                else
                  c.toJson(),
            ],
          }),
        );
        scheduleSave();
      }
    } else if (card.type == 'url' && card.ref != null && validUrl(card.ref!)) {
      await launchUrl(
        Uri.parse(card.ref!),
        mode: LaunchMode.externalApplication,
      );
    } else {
      final path = card.type == 'task'
          ? widget.index?.tasks
                .where((t) => t.id == card.ref)
                .firstOrNull
                ?.notePath
          : widget.index?.notes
                .where((n) => n.id == card.ref)
                .firstOrNull
                ?.path;
      if (path != null && widget.onOpenPath != null) {
        Navigator.of(context).pop();
        widget.onOpenPath!(path);
      }
    }
  }

  void addFrame() async {
    final title = await prompt('Frame title');
    if (title == null || !mounted) return;
    final p = centre;
    setState(
      () => board = Board.fromJson({
        ...board.toJson(),
        'frames': [
          ...board.frames.map((f) => f.toJson()),
          BoardFrame(
            id: newId(),
            title: title,
            x: p.dx - 300,
            y: p.dy - 200,
            w: 600,
            h: 400,
          ).toJson(),
        ],
      }),
    );
    scheduleSave();
  }

  void finishEdge(BoardCard from, Offset global) {
    final box = viewerKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final p =
        transform.toScene(box.globalToLocal(global)) -
        const Offset(origin, origin);
    final target = board.cards
        .where(
          (c) =>
              c.id != from.id &&
              Rect.fromLTWH(
                c.x.toDouble(),
                c.y.toDouble(),
                c.w.toDouble(),
                c.h.toDouble(),
              ).contains(p),
        )
        .firstOrNull;
    if (target == null) return;
    setState(
      () => board = board.addEdge(
        BoardEdge(id: newId(), from: from.id, to: target.id),
      ),
    );
    scheduleSave();
  }

  Widget edgeHitTarget(BoardEdge edge, BoardCard from, BoardCard to) {
    final start = Offset(
      from.x.toDouble() + from.w / 2,
      from.y.toDouble() + from.h / 2,
    );
    final end = Offset(to.x.toDouble() + to.w / 2, to.y.toDouble() + to.h / 2);
    final delta = end - start;
    final extent = delta.distance + 24;
    return Positioned(
      left: (start.dx + end.dx) / 2 + origin - extent / 2,
      top: (start.dy + end.dy) / 2 + origin - extent / 2,
      width: extent,
      height: extent,
      child: Center(
        child: Transform.rotate(
          angle: math.atan2(delta.dy, delta.dx),
          child: GestureDetector(
            key: ValueKey('edge-${edge.id}'),
            behavior: HitTestBehavior.translucent,
            onTap: () => setState(() {
              selectedEdge = edge.id;
              selected = null;
            }),
            child: SizedBox(width: delta.distance, height: 24),
          ),
        ),
      ),
    );
  }

  Widget content(BoardCard card) {
    final ref = card.ref;
    if (card.type == 'text') {
      return Text(
        card.text ?? '',
        maxLines: 6,
        overflow: TextOverflow.ellipsis,
      );
    }
    if (card.type == 'url' &&
        ref != null &&
        Uri.tryParse(ref)?.host.isNotEmpty == true) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(Uri.parse(ref).host, maxLines: 1),
          Text(ref, maxLines: 3, overflow: TextOverflow.ellipsis),
        ],
      );
    }
    if (card.type == 'asset' && ref != null) {
      return FutureBuilder<Uint8List?>(
        future:
            widget.imageResolver?.call(ref) ??
            widget.storage
                .readBytes(ref)
                .then<Uint8List?>((v) => v)
                .catchError((_) => null),
        builder: (_, snapshot) => snapshot.hasData
            ? Image.memory(
                snapshot.data!,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const Text('missing'),
              )
            : snapshot.connectionState == ConnectionState.done
            ? const Text('missing')
            : const CircularProgressIndicator(),
      );
    }
    if (card.type == 'note' || card.type == 'entity') {
      final note = widget.index?.notes.where((n) => n.id == ref).firstOrNull;
      if (note != null) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(iconForKind(note.kind), size: 18),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    note.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            FutureBuilder<String>(
              future: widget.storage.readText(note.path),
              builder: (_, s) => Text(
                s.data ?? '',
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        );
      }
    }
    if (card.type == 'task') {
      final task = widget.index?.tasks.where((t) => t.id == ref).firstOrNull;
      if (task != null) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(task.text, maxLines: 3, overflow: TextOverflow.ellipsis),
            Text(task.status),
          ],
        );
      }
    }
    return const Text('missing');
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(board.title),
      actions: [
        PopupMenuButton<String>(
          tooltip: 'Add',
          icon: const Icon(Icons.add),
          onSelected: add,
          itemBuilder: (_) => [
            for (final item in [
              'Note/entity',
              'Task',
              'Text',
              'Link',
              'Image from file',
            ])
              PopupMenuItem(value: item, child: Text(item)),
          ],
        ),
        IconButton(
          tooltip: 'Frame',
          onPressed: addFrame,
          icon: const Icon(Icons.crop_square),
        ),
        IconButton(
          tooltip: 'Connect',
          isSelected: connecting,
          onPressed: () => setState(() => connecting = !connecting),
          icon: const Icon(Icons.share),
        ),
        IconButton(
          tooltip: 'Delete selected card',
          onPressed: selected == null && selectedEdge == null ? null : delete,
          icon: const Icon(Icons.delete_outline),
        ),
      ],
    ),
    body: Focus(
      autofocus: true,
      onKeyEvent: (_, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.keyV &&
            (HardwareKeyboard.instance.isControlPressed ||
                HardwareKeyboard.instance.isMetaPressed)) {
          paste();
          return KeyEventResult.handled;
        }
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.delete ||
                event.logicalKey == LogicalKeyboardKey.backspace)) {
          delete();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: LayoutBuilder(
        builder: (context, constraints) {
          size = Size(constraints.maxWidth, constraints.maxHeight);
          final a = transform.toScene(Offset.zero),
              b = transform.toScene(Offset(size.width, size.height));
          final visible = board.cardsInRect(
            a.dx - origin,
            a.dy - origin,
            b.dx - a.dx,
            b.dy - a.dy,
          );
          return InteractiveViewer(
            key: viewerKey,
            transformationController: transform,
            constrained: false,
            boundaryMargin: const EdgeInsets.all(double.infinity),
            minScale: 0.1,
            maxScale: 4,
            child: SizedBox(
              width: 100000,
              height: 100000,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  for (final frame in board.frames)
                    Positioned(
                      left: frame.x.toDouble() + origin,
                      top: frame.y.toDouble() + origin,
                      width: frame.w.toDouble(),
                      height: frame.h.toDouble(),
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: Theme.of(context).colorScheme.outline,
                          ),
                          color: Theme.of(context)
                              .colorScheme
                              .surfaceContainerHighest
                              .withValues(alpha: 0.3),
                        ),
                        child: Align(
                          alignment: Alignment.topLeft,
                          child: GestureDetector(
                            key: ValueKey('frame-${frame.id}'),
                            onPanStart: (_) => dragPosition = Offset(
                              frame.x.toDouble(),
                              frame.y.toDouble(),
                            ),
                            onPanUpdate: (d) {
                              dragPosition +=
                                  d.delta / transform.value.getMaxScaleOnAxis();
                              setState(
                                () => board = board.moveFrame(
                                  frame.id,
                                  dragPosition.dx,
                                  dragPosition.dy,
                                ),
                              );
                              scheduleSave();
                            },
                            child: Padding(
                              padding: const EdgeInsets.all(8),
                              child: Text(frame.title),
                            ),
                          ),
                        ),
                      ),
                    ),
                  Positioned.fill(
                    child: IgnorePointer(
                      child: CustomPaint(
                        painter: _EdgePainter(
                          board,
                          selectedEdge,
                          Theme.of(context).colorScheme,
                        ),
                      ),
                    ),
                  ),
                  for (final edge in board.edges)
                    if (board.cards.where((c) => c.id == edge.from).firstOrNull
                        case final from?)
                      if (board.cards.where((c) => c.id == edge.to).firstOrNull
                          case final to?)
                        edgeHitTarget(edge, from, to),
                  for (final card in visible)
                    Positioned(
                      left: card.x.toDouble() + origin,
                      top: card.y.toDouble() + origin,
                      width: card.w.toDouble(),
                      height: card.h.toDouble(),
                      child: GestureDetector(
                        key: ValueKey('board-card-${card.id}'),
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          setState(() {
                            selected = card.id;
                            selectedEdge = null;
                          });
                          if (!connecting) openCard(card);
                        },
                        onPanStart: (_) {
                          dragPosition = Offset(
                            card.x.toDouble(),
                            card.y.toDouble(),
                          );
                          setState(() => selected = card.id);
                        },
                        onPanUpdate: (d) {
                          final scale = transform.value.getMaxScaleOnAxis();
                          dragPosition += d.delta / scale;
                          setState(
                            () => board = board.moveCard(
                              card.id,
                              dragPosition.dx,
                              dragPosition.dy,
                            ),
                          );
                          scheduleSave();
                        },
                        child: Card(
                          color: selected == card.id
                              ? Theme.of(context).colorScheme.secondaryContainer
                              : null,
                          child: Stack(
                            children: [
                              Positioned.fill(
                                child: Padding(
                                  padding: const EdgeInsets.all(10),
                                  child: ClipRect(child: content(card)),
                                ),
                              ),
                              if (connecting)
                                Positioned(
                                  right: 0,
                                  top: 4,
                                  child: GestureDetector(
                                    key: ValueKey('connect-${card.id}'),
                                    onPanEnd: (d) =>
                                        finishEdge(card, d.globalPosition),
                                    child: const Icon(
                                      Icons.radio_button_checked,
                                      size: 28,
                                    ),
                                  ),
                                ),
                              Positioned(
                                right: 0,
                                bottom: 0,
                                child: GestureDetector(
                                  key: ValueKey('resize-${card.id}'),
                                  onPanUpdate: (d) {
                                    final scale = transform.value
                                        .getMaxScaleOnAxis();
                                    setState(
                                      () => board = board.resizeCard(
                                        card.id,
                                        (card.w + d.delta.dx / scale).clamp(
                                          80,
                                          2000,
                                        ),
                                        (card.h + d.delta.dy / scale).clamp(
                                          50,
                                          2000,
                                        ),
                                      ),
                                    );
                                    scheduleSave();
                                  },
                                  child: const Icon(
                                    Icons.drag_handle,
                                    size: 20,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    ),
  );
}

class _EdgePainter extends CustomPainter {
  _EdgePainter(this.board, this.selected, this.colors);
  final Board board;
  final String? selected;
  final ColorScheme colors;
  @override
  void paint(Canvas canvas, Size size) {
    for (final edge in board.edges) {
      final a = board.cards.where((c) => c.id == edge.from).firstOrNull;
      final b = board.cards.where((c) => c.id == edge.to).firstOrNull;
      if (a == null || b == null) continue;
      final start = Offset(
        a.x.toDouble() + a.w / 2 + _WhiteboardState.origin,
        a.y.toDouble() + a.h / 2 + _WhiteboardState.origin,
      );
      final end = Offset(
        b.x.toDouble() + b.w / 2 + _WhiteboardState.origin,
        b.y.toDouble() + b.h / 2 + _WhiteboardState.origin,
      );
      final delta = end - start;
      if (delta.distance == 0) continue;
      final unit = delta / delta.distance;
      final t = math.min(
        (b.w / 2) / (unit.dx.abs() + 0.00001),
        (b.h / 2) / (unit.dy.abs() + 0.00001),
      );
      final tip = end - unit * t;
      final paint = Paint()
        ..color = edge.id == selected ? colors.primary : colors.outline
        ..strokeWidth = edge.id == selected ? 3 : 2;
      canvas.drawLine(start, tip, paint);
      final side = Offset(-unit.dy, unit.dx);
      canvas.drawLine(tip, tip - unit * 12 + side * 6, paint);
      canvas.drawLine(tip, tip - unit * 12 - side * 6, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _EdgePainter oldDelegate) => true;
}
