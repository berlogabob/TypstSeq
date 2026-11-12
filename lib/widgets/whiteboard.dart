import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:tylog_core/tylog_core.dart';

import '../github/github_client.dart';
import '../github/github_projects.dart';
import 'constants.dart';
import 'entity_tree.dart';
import 'note_picker_sheet.dart';

String boardNotePreview(String source) {
  final text = source.trimLeft();
  final header = RegExp(
    r'^#show: tylog\.note',
    multiLine: true,
  ).firstMatch(text);
  var body = 0;
  if (header != null) {
    // Skip the whole header call, which usually spans several lines; quoted
    // values may contain parentheses.
    var depth = 0;
    var quoted = false;
    for (
      var i = text.indexOf('(', header.start);
      i >= 0 && i < text.length;
      i++
    ) {
      final c = text[i];
      if (quoted) {
        if (c == '\\') {
          i++;
        } else if (c == '"') {
          quoted = false;
        }
      } else if (c == '"') {
        quoted = true;
      } else if (c == '(') {
        depth++;
      } else if (c == ')' && --depth == 0) {
        body = i + 1;
        break;
      }
    }
  }
  return text
      .substring(body)
      .split('\n')
      .skipWhile((line) => line.trim().isEmpty || line.startsWith('#import '))
      .join('\n')
      .trimLeft();
}

class BoardsTab extends StatefulWidget {
  const BoardsTab({
    super.key,
    required this.storage,
    required this.index,
    this.imageResolver,
    this.onOpenPath,
    this.onOpenColumns,
    this.githubClient,
    this.deviceId = 'unknown',
  });
  final Future<GitHubClient> Function()? githubClient;
  final void Function(BuildContext, Board)? onOpenColumns;
  final String deviceId;
  final VaultStorage storage;
  final VaultIndex? index;
  final Future<Uint8List?> Function(String)? imageResolver;
  final ValueChanged<String>? onOpenPath;
  @override
  State<BoardsTab> createState() => _BoardsTabState();
}

class _BoardsTabState extends State<BoardsTab> {
  late Future<List<Board>> boards = load();
  final hashes = <String, String>{};
  Future<List<Board>> load() async {
    final entries = await widget.storage.list(path: 'boards');
    final result = <Board>[];
    for (final entry in entries) {
      if (!entry.isDirectory && entry.path.endsWith('.board.json')) {
        try {
          final text = await widget.storage.readText(entry.path);
          final board = parseBoard(text);
          hashes[board.id] = sha256.convert(utf8.encode(text)).toString();
          result.add(board);
        } catch (_) {
          /* Keep other boards accessible. */
        }
      }
    }
    final index = widget.index;
    if (index != null) {
      final children = childrenByParent(index.notes);
      for (final entity in index.notes) {
        final scoped = result
            .where(
              (board) =>
                  board.scopeEntity == entity.id ||
                  (board.id == entity.id &&
                      board.scopeExtra['github_project'] is! Map),
            )
            .toList();
        if (scoped.isEmpty && structuralNoteKinds.contains(entity.kind)) {
          continue;
        }
        if (scoped.isEmpty &&
            !hasBoardItems(entity.id, index) &&
            (children[entity.id]?.isEmpty ?? true)) {
          continue;
        }
        result.removeWhere((board) => scoped.contains(board));
        result.add(
          Board(
            id:
                scoped.where((b) => b.id == entity.id).firstOrNull?.id ??
                scoped
                    .where((b) => b.id != '${entity.id}-wb')
                    .firstOrNull
                    ?.id ??
                entity.id,
            title: entity.title,
            scopeEntity: entity.id,
          ),
        );
      }
    }
    return result..sort((a, b) => a.title.compareTo(b.title));
  }

  Future<void> open(Board board, {bool create = false}) async {
    if (create) {
      await writeBoard(widget.storage, board);
      hashes[board.id] = await widget.storage.hash(boardPath(board.id));
    }
    if (board.scopeEntity != null ||
        board.scopeExtra['github_project'] is Map ||
        board.layout == 'columns') {
      if (mounted) widget.onOpenColumns?.call(context, board);
      return;
    }
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => Whiteboard(
          board: board,
          initialHash: hashes[board.id],
          deviceId: widget.deviceId,
          storage: widget.storage,
          index: widget.index,
          imageResolver: widget.imageResolver,
          onOpenPath: widget.onOpenPath,
        ),
      ),
    );
    if (mounted) setState(() => boards = load());
  }

  Future<void> newProjectBoard() async {
    try {
      final projects = await GitHubProjects(
        await widget.githubClient!(),
      ).fetchProjectsFromGitHub();
      if (!mounted) return;
      final project = await showDialog<GitHubProject>(
        context: context,
        builder: (context) => SimpleDialog(
          title: const Text('Choose a GitHub project'),
          children: [
            for (final project in projects)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(context, project),
                child: Text(
                  '${project.owner} · ${project.title} (#${project.number})',
                ),
              ),
            if (projects.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('No projects found'),
              ),
          ],
        ),
      );
      if (project == null || !mounted) return;
      await open(
        Board(
          id: 'github-${DateTime.now().microsecondsSinceEpoch}',
          title: project.title,
          scopeExtra: {
            'github_project': {
              'owner': project.owner,
              'number': project.number,
            },
          },
        ),
        create: true,
      );
      if (mounted) setState(() => boards = load());
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not load GitHub projects: $error')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      if (widget.githubClient != null)
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: newProjectBoard,
            icon: const Icon(Icons.add),
            label: const Text('New GitHub project board'),
          ),
        ),
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
                    leading: board.scopeEntity == null
                        ? null
                        : Icon(
                            iconForKind(
                              widget.index?.notes
                                      .where((n) => n.id == board.scopeEntity)
                                      .firstOrNull
                                      ?.kind ??
                                  'note',
                            ),
                          ),
                    title: Text(board.title),
                    subtitle: Text(
                      board.scopeEntity != null && widget.index != null
                          ? '${tasksForEntity(board.scopeEntity!, widget.index!).length} tasks · ${issuesForEntity(board.scopeEntity!, widget.index!).length} issues · ${childrenByParent(widget.index!.notes)[board.scopeEntity]?.length ?? 0} ${childrenByParent(widget.index!.notes)[board.scopeEntity]?.length == 1 ? 'child' : 'children'}'
                          : '${board.layout} · ${board.cards.length} cards',
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
  String deviceId = 'unknown',
}) async {
  final id = '$entityId-wb';
  final path = boardPath(id);
  late Board board;
  late String hash;
  if (await storage.exists(path)) {
    final text = await storage.readText(path);
    board = parseBoard(text);
    hash = sha256.convert(utf8.encode(text)).toString();
  } else {
    board = Board(id: id, title: title, layout: 'free', scopeEntity: entityId);
    await writeBoard(storage, board);
    hash = await storage.hash(path);
  }
  if (!context.mounted) return;
  await Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => Whiteboard(
        board: board,
        initialHash: hash,
        deviceId: deviceId,
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
    this.initialHash,
    this.deviceId = 'unknown',
    this.embedded = false,
    this.registerFlush,
  });
  final bool embedded;
  final void Function(Future<void> Function())? registerFlush;
  final String? initialHash;
  final String deviceId;
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
  String? savedHash;
  late Future<void> hashReady;
  bool saveFailed = false;
  int generation = 0;
  bool leaving = false;
  String? selected;
  String? selectedEdge;
  bool connecting = false;
  final viewerKey = GlobalKey();
  Offset dragPosition = Offset.zero;
  Set<String> frameCardIds = {};
  Size size = Size.zero;
  final imageFutures = <String, Future<Uint8List?>>{};
  final noteFutures = <String, Future<String>>{};
  final imageVersions = <String, Future<Uint8List?>>{};
  final noteVersions = <String, Future<String>>{};

  @override
  void didUpdateWidget(covariant Whiteboard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.index != widget.index ||
        oldWidget.storage != widget.storage ||
        oldWidget.imageResolver != widget.imageResolver) {
      imageFutures.clear();
      noteFutures.clear();
    }
  }

  Future<Uint8List?> imageContent(String ref) =>
      imageFutures.putIfAbsent(ref, () async {
        try {
          final hash = await widget.storage
              .hash(ref)
              .catchError((_) => 'resolver');
          return await imageVersions.putIfAbsent(
            '$ref:$hash',
            () async =>
                await (widget.imageResolver?.call(ref) ??
                    widget.storage.readBytes(ref)),
          );
        } catch (_) {
          return null;
        }
      });

  Future<String> noteContent(NoteRef note) => noteFutures.putIfAbsent(
    '${note.id}:${note.path}:${note.contentHash ?? note.fingerprint}',
    () async {
      final hash = note.contentHash ?? await widget.storage.hash(note.path);
      return noteVersions.putIfAbsent(
        '${note.id}:${note.path}:$hash',
        () => widget.storage.readText(note.path),
      );
    },
  );

  void moveSelected(Offset delta) {
    final card = board.cards.where((c) => c.id == selected).firstOrNull;
    if (card == null) return;
    setState(
      () =>
          board = board.moveCard(card.id, card.x + delta.dx, card.y + delta.dy),
    );
    scheduleSave();
  }

  @override
  void initState() {
    super.initState();
    widget.registerFlush?.call(() async {
      if (timer != null) save();
      await writes;
      if (saveFailed) throw StateError('Whiteboard could not be saved');
    });
    hashReady = () async {
      savedHash = widget.initialHash;
      if (savedHash == null &&
          await widget.storage.exists(boardPath(board.id))) {
        savedHash = await widget.storage.hash(boardPath(board.id));
      }
    }();
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
    final saveGeneration = generation;
    writes = writes
        .then((_) async {
          await hashReady;
          if (saveGeneration != generation) return;
          final path = boardPath(snapshot.id);
          final currentHash = await widget.storage.exists(path)
              ? await widget.storage.hash(path)
              : null;
          if (currentHash != null && currentHash != savedHash) {
            var copyId = '${snapshot.id}.conflict-${widget.deviceId}';
            if (await widget.storage.exists(boardPath(copyId))) {
              copyId = '$copyId-${DateTime.now().microsecondsSinceEpoch}';
            }
            timer?.cancel();
            timer = null;
            await widget.storage.writeText(
              boardPath(copyId),
              encodeBoard(Board.fromJson({...board.toJson(), 'id': copyId})),
            );
            final text = await widget.storage.readText(path);
            final synced = parseBoard(text);
            savedHash = sha256.convert(utf8.encode(text)).toString();
            generation++;
            if (mounted) {
              setState(() => board = synced);
              final v = synced.viewport;
              transform.removeListener(viewportChanged);
              transform.value = Matrix4.identity()
                ..translateByDouble(
                  v.x.toDouble() - origin * v.zoom,
                  v.y.toDouble() - origin * v.zoom,
                  0,
                  1,
                )
                ..scaleByDouble(v.zoom.toDouble(), v.zoom.toDouble(), 1, 1);
              transform.addListener(viewportChanged);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Board changed on another device - your version saved as a copy',
                  ),
                ),
              );
            }
            return;
          }
          await writeBoard(widget.storage, snapshot);
          saveFailed = false;
          savedHash = await widget.storage.hash(path);
        })
        .catchError((Object e) {
          if (mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text('Could not save board: $e')));
          }
          saveFailed = true;
        });
  }

  Future<void> leave() async {
    if (leaving) return;
    leaving = true;
    if (timer != null) save();
    try {
      await writes;
      if (mounted && !saveFailed) {
        Navigator.of(context).pop();
      } else {
        leaving = false;
      }
    } catch (_) {
      leaving = false;
    }
  }

  @override
  void dispose() {
    if (timer != null) {
      save();
      unawaited(writes.catchError((Object _) {}));
    }
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
      if (type == 'Add from OpenLabTwin') {
        addOltTree();
      } else if (type == 'Note/entity') {
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
        if (result.isEmpty) return;
        final file = result.single;
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

  Widget edgeHitTarget(BoardEdge edge, Rect from, Rect to) {
    final start = from.center;
    final end = to.center;
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
          child: Semantics(
            label: 'Edge from ${edge.from} to ${edge.to}',
            button: true,
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
      ),
    );
  }

  Board get treeBoard {
    final layout = layoutTree(
      board.scopeEntity!,
      childrenByParent(widget.index?.notes ?? []),
    );
    return Board(
      id: board.id,
      title: board.title,
      layout: 'free',
      cards: [
        for (final entry in layout.positions.entries)
          BoardCard(
            id: entry.key,
            type: 'entity',
            ref: entry.key,
            x: entry.value.x,
            y: entry.value.y,
          ),
      ],
      edges: [
        for (var i = 0; i < layout.edges.length; i++)
          BoardEdge(
            id: 'tree-$i',
            from: layout.edges[i].from,
            to: layout.edges[i].to,
          ),
      ],
    );
  }

  void addOltTree() {
    final notes = (widget.index?.notes ?? <NoteRef>[])
        .where(
          (n) =>
              n.path.startsWith('olt:place:') ||
              n.path.startsWith('olt:asset:'),
        )
        .toList();
    if (notes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No OpenLabTwin places or assets cached')),
      );
      return;
    }
    final roots = buildEntityTree(notes, notes.map((n) => n.path).toSet());
    final children = childrenByParent(notes);
    const root = 'olt:board-root';
    children[root] = roots.map((n) => n.note).toList();
    final layout = layoutTree(root, children);
    final point = centre;
    pinBoard(
      Board(
        id: board.id,
        title: board.title,
        cards: [
          for (final e in layout.positions.entries)
            if (e.key != root)
              BoardCard(
                id: e.key,
                type: 'entity',
                ref: e.key,
                x: e.value.x + point.dx - 120,
                y: e.value.y + point.dy - 240,
              ),
        ],
        edges: [
          for (var i = 0; i < layout.edges.length; i++)
            if (layout.edges[i].from != root)
              BoardEdge(
                id: 'olt-$i',
                from: layout.edges[i].from,
                to: layout.edges[i].to,
              ),
        ],
      ),
    );
  }

  void pinTree() {
    final tree = treeBoard;
    if (tree.cards.length <= 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Nothing is part of ${board.title} yet. Add "Part of" on a page.',
          ),
        ),
      );
      return;
    }
    pinBoard(tree);
  }

  void pinBoard(Board tree) {
    final ids = <String, String>{};
    var next = board;
    final stamp = newId();
    var serial = 0;
    for (final card in tree.cards) {
      final existing = next.cards
          .where(
            (c) =>
                (c.type == 'entity' || c.type == 'note') && c.ref == card.ref,
          )
          .firstOrNull;
      if (existing != null) {
        ids[card.id] = existing.id;
      } else {
        final id = '$stamp-${serial++}';
        ids[card.id] = id;
        final note = widget.index?.notes
            .where((n) => n.id == card.ref)
            .firstOrNull;
        next = next.addCard(
          BoardCard(
            id: id,
            type: note?.kind == 'note' ? 'note' : 'entity',
            ref: card.ref,
            x: card.x,
            y: card.y,
          ),
        );
      }
    }
    for (final edge in tree.edges) {
      if (next.edges.any(
        (e) => e.from == ids[edge.from] && e.to == ids[edge.to],
      )) {
        continue;
      }
      next = next.addEdge(
        BoardEdge(
          id: '$stamp-${serial++}',
          from: ids[edge.from]!,
          to: ids[edge.to]!,
        ),
      );
    }
    setState(() => board = next);
    save();
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
        future: imageContent(ref),
        builder: (_, snapshot) => snapshot.hasData
            ? Image.memory(
                snapshot.data!,
                fit: BoxFit.cover,
                cacheWidth: math.max(
                  1,
                  ((card.w - 20) * MediaQuery.devicePixelRatioOf(context))
                      .round(),
                ),
                cacheHeight: math.max(
                  1,
                  ((card.h - 20) * MediaQuery.devicePixelRatioOf(context))
                      .round(),
                ),
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
            if (note.path.startsWith('olt:')) ...[
              const Text('OpenLabTwin'),
              for (final row in (note.properties['stock'] as List? ?? const []))
                if (note.path.startsWith('olt:asset:') &&
                    row is Map &&
                    row['qty'] != null)
                  Builder(
                    builder: (context) {
                      final qty = row['qty'];
                      final low = qty is num && qty <= 0;
                      final colors = Theme.of(context).colorScheme;
                      return Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: low
                              ? colors.errorContainer
                              : colors.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(kRadiusSmall),
                        ),
                        child: Text(
                          'Stock: $qty${row['unit'] == null ? '' : ' ${row['unit']}'}',
                          style: TextStyle(
                            color: low
                                ? colors.onErrorContainer
                                : colors.onSurface,
                          ),
                        ),
                      );
                    },
                  ),
            ] else
              FutureBuilder<String>(
                future: noteContent(note),
                builder: (_, s) => Text(
                  s.data == null ? '' : boardNotePreview(s.data!),
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
  Widget build(BuildContext context) => widget.embedded
      ? buildCanvas()
      : PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) leave();
          },
          child: buildCanvas(),
        );

  Widget buildCanvas() => Scaffold(
    appBar: AppBar(
      automaticallyImplyLeading: !widget.embedded,
      leading: widget.embedded ? null : BackButton(onPressed: leave),
      title: widget.embedded ? null : Text(board.title),
      actions: [
        if (board.scopeEntity != null)
          TextButton(
            key: const Key('board-add-contents'),
            onPressed: pinTree,
            child: const Text('Add contained pages'),
          ),
        IconButton(
          tooltip: 'Paste',
          onPressed: paste,
          icon: const Icon(Icons.content_paste),
        ),
        PopupMenuButton<String>(
          tooltip: 'Add',
          icon: const Icon(Icons.add),
          onSelected: add,
          itemBuilder: (_) => [
            for (final item in [
              'Add from OpenLabTwin',
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
        if (selected != null)
          IconButton(
            tooltip: 'Open selected card',
            onPressed: () =>
                openCard(board.cards.firstWhere((c) => c.id == selected)),
            icon: const Icon(Icons.open_in_new),
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
        if (event is KeyDownEvent && selected != null) {
          final delta = switch (event.logicalKey) {
            LogicalKeyboardKey.arrowLeft => const Offset(-8, 0),
            LogicalKeyboardKey.arrowRight => const Offset(8, 0),
            LogicalKeyboardKey.arrowUp => const Offset(0, -8),
            LogicalKeyboardKey.arrowDown => const Offset(0, 8),
            _ => null,
          };
          if (delta != null) {
            moveSelected(delta);
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.enter ||
              event.logicalKey == LogicalKeyboardKey.numpadEnter) {
            openCard(board.cards.firstWhere((c) => c.id == selected));
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: LayoutBuilder(
        builder: (context, constraints) {
          final displayBoard = board;
          size = Size(constraints.maxWidth, constraints.maxHeight);
          final a = transform.toScene(Offset.zero),
              b = transform.toScene(Offset(size.width, size.height));
          final visible = displayBoard.cardsInRect(
            a.dx - origin,
            a.dy - origin,
            b.dx - a.dx,
            b.dy - a.dy,
          );
          final rects = {
            for (final c in displayBoard.cards)
              c.id: Rect.fromLTWH(
                c.x.toDouble(),
                c.y.toDouble(),
                c.w.toDouble(),
                c.h.toDouble(),
              ),
          };
          final visibleIds = visible.map((c) => c.id).toSet();
          final visibleEdges = displayBoard.edges
              .where(
                (e) => visibleIds.contains(e.from) || visibleIds.contains(e.to),
              )
              .toList();
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
                  if (board.cards.isEmpty)
                    Positioned(
                      left:
                          centre.dx -
                          math.min(size.width - 32, 360) / 2 +
                          origin,
                      top: centre.dy - 80 + origin,
                      width: math.min(size.width - 32, 360),
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'This whiteboard is empty',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const SizedBox(height: 4),
                              const Text(
                                'Choose Add to place your first card.',
                              ),
                              TextButton.icon(
                                onPressed: () => add('Text'),
                                icon: const Icon(Icons.add),
                                label: const Text('Add text card'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  for (final frame in displayBoard.frames)
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
                            onPanStart: (_) {
                              dragPosition = Offset(
                                frame.x.toDouble(),
                                frame.y.toDouble(),
                              );
                              frameCardIds = board.cards
                                  .where(
                                    (c) =>
                                        c.x + c.w / 2 >= frame.x &&
                                        c.x + c.w / 2 <= frame.x + frame.w &&
                                        c.y + c.h / 2 >= frame.y &&
                                        c.y + c.h / 2 <= frame.y + frame.h,
                                  )
                                  .map((c) => c.id)
                                  .toSet();
                            },
                            onPanUpdate: (d) {
                              dragPosition +=
                                  d.delta / transform.value.getMaxScaleOnAxis();
                              setState(
                                () => board = board.moveFrame(
                                  frame.id,
                                  dragPosition.dx,
                                  dragPosition.dy,
                                  cardIds: frameCardIds,
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
                          visibleEdges,
                          rects,
                          selectedEdge,
                          Theme.of(context).colorScheme,
                        ),
                      ),
                    ),
                  ),
                  for (final edge in visibleEdges)
                    if (rects[edge.from] case final from?)
                      if (rects[edge.to] case final to?)
                        edgeHitTarget(edge, from, to),
                  for (final card in visible)
                    Positioned(
                      left: card.x.toDouble() + origin,
                      top: card.y.toDouble() + origin,
                      width: card.w.toDouble(),
                      height: card.h.toDouble(),
                      child: Semantics(
                        label:
                            '${card.type} card ${card.text ?? card.ref ?? card.id}',
                        selected: selected == card.id,
                        child: GestureDetector(
                          key: ValueKey('board-card-${card.id}'),
                          behavior: HitTestBehavior.opaque,
                          onTap: () {
                            setState(() {
                              selected = card.id;
                              selectedEdge = null;
                            });
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
                                ? Theme.of(
                                    context,
                                  ).colorScheme.secondaryContainer
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
                                    child: Semantics(
                                      label: 'Connect card ${card.id}',
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
                                  ),
                                Positioned(
                                  right: 0,
                                  bottom: 0,
                                  child: Semantics(
                                    label: 'Resize card ${card.id}',
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
                                ),
                              ],
                            ),
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
  _EdgePainter(this.edges, this.rects, this.selected, this.colors);
  final List<BoardEdge> edges;
  final Map<String, Rect> rects;
  final String? selected;
  final ColorScheme colors;
  @override
  void paint(Canvas canvas, Size size) {
    for (final edge in edges) {
      final a = rects[edge.from];
      final b = rects[edge.to];
      if (a == null || b == null) continue;
      final start = Offset(
        a.center.dx + _WhiteboardState.origin,
        a.center.dy + _WhiteboardState.origin,
      );
      final end = Offset(
        b.center.dx + _WhiteboardState.origin,
        b.center.dy + _WhiteboardState.origin,
      );
      final delta = end - start;
      if (delta.distance == 0) continue;
      final unit = delta / delta.distance;
      final t = math.min(
        (b.width / 2) / (unit.dx.abs() + 0.00001),
        (b.height / 2) / (unit.dy.abs() + 0.00001),
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
