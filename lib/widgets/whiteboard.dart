import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tylog_core/tylog_core.dart';

import 'constants.dart';

class BoardsTab extends StatefulWidget {
  const BoardsTab({
    super.key,
    required this.storage,
    required this.index,
    this.imageResolver,
  });
  final VaultStorage storage;
  final VaultIndex? index;
  final Future<Uint8List?> Function(String)? imageResolver;
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
  });
  final Board board;
  final VaultStorage storage;
  final VaultIndex? index;
  final Future<Uint8List?> Function(String)? imageResolver;
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
    if (selected == null) return;
    setState(() {
      board = board.removeCard(selected!);
      selected = null;
    });
    scheduleSave();
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
    if (card.type == 'asset' && ref != null && widget.imageResolver != null) {
      return FutureBuilder<Uint8List?>(
        future: widget.imageResolver!(ref),
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
        IconButton(
          tooltip: 'Delete selected card',
          onPressed: selected == null ? null : delete,
          icon: const Icon(Icons.delete_outline),
        ),
      ],
    ),
    body: Focus(
      autofocus: true,
      onKeyEvent: (_, event) {
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
                  for (final card in visible)
                    Positioned(
                      left: card.x.toDouble() + origin,
                      top: card.y.toDouble() + origin,
                      width: card.w.toDouble(),
                      height: card.h.toDouble(),
                      child: GestureDetector(
                        key: ValueKey('board-card-${card.id}'),
                        behavior: HitTestBehavior.opaque,
                        onTap: () => setState(() => selected = card.id),
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
