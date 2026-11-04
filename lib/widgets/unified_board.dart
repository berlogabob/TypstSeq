import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:tylog_core/tylog_core.dart';

import '../github/github_client.dart';
import '../vault.dart';
import 'entity_board.dart';
import 'whiteboard.dart';

class UnifiedBoard extends StatefulWidget {
  const UnifiedBoard({
    super.key,
    required this.entity,
    required this.vault,
    required this.index,
    required this.setStatus,
    required this.mutateNote,
    required this.refreshIndex,
    this.sourceBoardId,
    this.githubClient,
    this.onOpenUrl,
    this.onOpenPath,
    this.imageResolver,
    this.deviceId = 'unknown',
  });
  final String? sourceBoardId;
  final NoteRef entity;
  final Vault vault;
  final VaultIndex index;
  final Future<void> Function(TaskRef, String) setStatus;
  final Future<bool> Function(String, String Function(String)) mutateNote;
  final Future<VaultIndex?> Function() refreshIndex;
  final Future<GitHubClient> Function()? githubClient;
  final void Function(String)? onOpenUrl;
  final ValueChanged<String>? onOpenPath;
  final Future<Uint8List?> Function(String)? imageResolver;
  final String deviceId;

  @override
  State<UnifiedBoard> createState() => _UnifiedBoardState();
}

class _UnifiedBoardState extends State<UnifiedBoard> {
  Board? board;
  String? hash;
  String layout = 'columns';
  bool busy = true;
  Future<void> Function()? flush;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final storage = widget.vault.storage;
      var saved = await readBoard(storage, widget.entity.id);
      if (saved == null &&
          widget.sourceBoardId != null &&
          widget.sourceBoardId != widget.entity.id &&
          widget.sourceBoardId != '${widget.entity.id}-wb') {
        final old = await readBoard(storage, widget.sourceBoardId!);
        if (old != null) {
          saved = Board.fromJson({...old.toJson(), 'id': widget.entity.id});
          await writeBoard(storage, saved);
          widget.vault.restoreWriteMarkers(
            boardPath(saved.id),
            stale: false,
            pendingSync: true,
          );
        }
      }
      saved ??= Board(
        id: widget.entity.id,
        title: widget.entity.title,
        scopeEntity: widget.entity.id,
        schema: 2,
      );
      hash = await storage.exists(boardPath(saved.id))
          ? await storage.hash(boardPath(saved.id))
          : null;
      layout = {'columns', 'free', 'tree'}.contains(saved.layout)
          ? saved.layout
          : 'columns';
      board = await canvasBoard(saved);
      if (!identical(board, saved)) {
        await writeBoard(storage, board!);
        widget.vault.restoreWriteMarkers(
          boardPath(saved.id),
          stale: false,
          pendingSync: true,
        );
        hash = await storage.hash(boardPath(saved.id));
      }
      if (mounted) setState(() => busy = false);
    } catch (e) {
      if (mounted) {
        setState(() => busy = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not load board: $e')));
      }
    }
  }

  Future<Board> canvasBoard(Board saved) async {
    if (saved.extra['legacy_canvas_migrated'] == true ||
        saved.cards.isNotEmpty ||
        saved.frames.isNotEmpty ||
        saved.edges.isNotEmpty) {
      return saved;
    }
    final fallback = await readBoard(
      widget.vault.storage,
      '${widget.entity.id}-wb',
    );
    if (fallback == null) return saved;
    return Board.fromJson({
      ...saved.toJson(),
      'schema': 2,
      'legacy_canvas_migrated': true,
      'cards': fallback.cards.map((c) => c.toJson()).toList(),
      'frames': fallback.frames.map((f) => f.toJson()).toList(),
      'edges': fallback.edges.map((e) => e.toJson()).toList(),
      'viewport': fallback.viewport.toJson(),
    });
  }

  Future<void> select(String value) async {
    if (busy || value == layout) return;
    setState(() => busy = true);
    try {
      await flush?.call();
      flush = null;
      final storage = widget.vault.storage;
      final current =
          await readBoard(storage, widget.entity.id) ??
          Board(
            id: widget.entity.id,
            title: widget.entity.title,
            scopeEntity: widget.entity.id,
          );
      final next = Board.fromJson({
        ...current.toJson(),
        'schema': 2,
        'layout': value,
      });
      await writeBoard(storage, next);
      widget.vault.restoreWriteMarkers(
        boardPath(next.id),
        stale: false,
        pendingSync: true,
      );
      hash = await storage.hash(boardPath(next.id));
      final canvas = await canvasBoard(next);
      if (mounted) {
        setState(() {
          layout = value;
          board = canvas;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not update board: $e')));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text('${widget.entity.title} Board')),
    body: board == null
        ? const Center(child: CircularProgressIndicator())
        : Column(
            children: [
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'columns', label: Text('Kanban')),
                  ButtonSegment(value: 'free', label: Text('Whiteboard')),
                  ButtonSegment(value: 'tree', label: Text('Tree')),
                ],
                selected: {layout},
                onSelectionChanged: busy
                    ? null
                    : (value) => select(value.single),
              ),
              Expanded(
                child: layout == 'columns'
                    ? EntityBoard(
                        key: const ValueKey('kanban'),
                        boardId: widget.entity.id,
                        entity: widget.entity,
                        vault: widget.vault,
                        index: widget.index,
                        setStatus: widget.setStatus,
                        mutateNote: widget.mutateNote,
                        refreshIndex: widget.refreshIndex,
                        githubClient: widget.githubClient,
                        onOpenUrl: widget.onOpenUrl,
                      )
                    : Whiteboard(
                        key: ValueKey(layout),
                        board: board!,
                        initialHash: hash,
                        storage: widget.vault.storage,
                        index: widget.index,
                        initialTree: layout == 'tree',
                        embedded: true,
                        registerFlush: (callback) => flush = callback,
                        onPinTree: () => select('free'),
                        deviceId: widget.deviceId,
                        imageResolver: widget.imageResolver,
                        onOpenPath: widget.onOpenPath,
                      ),
              ),
            ],
          ),
  );
}
