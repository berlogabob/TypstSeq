import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:tylog_core/tylog_core.dart';

import '../vault.dart';
import '../controlled_editor.dart';
import 'constants.dart';

class EntityBoard extends StatefulWidget {
  const EntityBoard({
    super.key,
    required this.entity,
    required this.vault,
    required this.index,
    required this.setStatus,
    required this.mutateNote,
    required this.refreshIndex,
  });

  final NoteRef entity;
  final Vault vault;
  final VaultIndex index;
  final Future<void> Function(TaskRef, String) setStatus;
  final Future<bool> Function(String, String Function(String)) mutateNote;
  final Future<VaultIndex?> Function() refreshIndex;

  @override
  State<EntityBoard> createState() => _EntityBoardState();
}

class _EntityBoardState extends State<EntityBoard> {
  late final String id = base64Url
      .encode(utf8.encode(widget.entity.id))
      .replaceAll('=', '');
  late Board board = Board(
    id: id,
    title: widget.entity.title,
    scopeEntity: widget.entity.id,
  );
  late VaultIndex index = widget.index;
  bool loading = true;
  bool busy = false;
  bool loadFailed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(EntityBoard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.index, widget.index)) index = widget.index;
  }

  Future<void> _load() async {
    try {
      final saved = await readBoard(widget.vault.storage, id);
      if (mounted) {
        setState(() {
          board = saved ?? board;
          loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          loading = false;
          loadFailed = true;
        });
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not load board: $e')));
      }
    }
  }

  Future<void> _drop(
    TaskRef task,
    String column,
    int position,
    List<TaskRef> cards,
  ) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      if (task.status != column) {
        final stopped =
            column == 'doing' &&
            index.tasks.any(
              (other) =>
                  (other.id != task.id || other.notePath != task.notePath) &&
                  other.runningClock != null,
            );
        await widget.setStatus(task, column);
        final updated = await widget.refreshIndex();
        if (!mounted) return;
        if (updated != null) index = updated;
        if (stopped &&
            index.tasks.any(
              (t) =>
                  t.id == task.id &&
                  t.notePath == task.notePath &&
                  t.runningClock != null,
            )) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Stopped the other running timer')),
          );
        }
      } else {
        if (loadFailed) throw StateError('Board file could not be read');
        final ordered = cards.map((t) => t.id).toList();
        final old = ordered.indexOf(task.id);
        if (old < 0) return;
        ordered.removeAt(old);
        if (old < position) position--;
        ordered.insert(position.clamp(0, ordered.length), task.id);
        final next = Board(
          id: board.id,
          title: board.title,
          layout: board.layout,
          scopeEntity: board.scopeEntity,
          scopeExtra: board.scopeExtra,
          columns: board.columns,
          order: {...board.order, column: ordered},
          extra: board.extra,
        );
        await writeBoard(widget.vault.storage, next);
        widget.vault.restoreWriteMarkers(
          boardPath(id),
          stale: false,
          pendingSync: true,
        );
        board = next;
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

  Future<void> _dropIssue(IssueRef issue, String column) async {
    if (busy || issue.status == column) return;
    setState(() => busy = true);
    try {
      if (!await widget.mutateNote(
        issue.notePath,
        (source) => setIssueStatus(source, issue, column),
      )) {
        throw StateError('Issue could not be saved');
      }
      final next = await widget.refreshIndex();
      if (mounted && next != null) index = next;
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
  Widget build(BuildContext context) {
    final tasks = tasksForEntity(widget.entity.id, index);
    final issues = issuesForEntity(widget.entity.id, index);
    final columns = [
      ...board.columns.values,
      if (board.columns.showCancelled &&
          !board.columns.values.contains('cancelled'))
        'cancelled',
    ];
    return Scaffold(
      appBar: AppBar(title: Text('${widget.entity.title} Board')),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final column in columns)
                    Builder(
                      builder: (context) {
                        final matching = tasks
                            .where((t) => t.status == column)
                            .toList();
                        final orderedIds = board.orderCards(
                          column,
                          matching.map((t) => t.id),
                        );
                        final cards = [
                          for (final id in orderedIds)
                            matching.firstWhere((t) => t.id == id),
                        ];
                        Widget target(int position, {bool fill = false}) =>
                            DragTarget<Object>(
                              onWillAcceptWithDetails: (_) => !busy,
                              onAcceptWithDetails: (details) {
                                final item = details.data;
                                if (item is TaskRef) {
                                  _drop(item, column, position, cards);
                                } else if (item is IssueRef) {
                                  _dropIssue(item, column);
                                }
                              },
                              builder: (context, candidates, rejected) =>
                                  Container(
                                    key: ValueKey('board-$column-$position'),
                                    height: fill
                                        ? null
                                        : (candidates.isEmpty ? 16 : 40),
                                    constraints: fill
                                        ? const BoxConstraints(minHeight: 16)
                                        : null,
                                    color: candidates.isEmpty
                                        ? Colors.transparent
                                        : Theme.of(
                                            context,
                                          ).colorScheme.primaryContainer,
                                  ),
                            );
                        return SizedBox(
                          key: ValueKey('board-column-$column'),
                          width: 260,
                          child: Padding(
                            padding: const EdgeInsets.all(8),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text(
                                  column.toUpperCase(),
                                  style: Theme.of(
                                    context,
                                  ).textTheme.titleMedium,
                                ),
                                Expanded(
                                  child: LayoutBuilder(
                                    builder: (context, constraints) => ListView(
                                      children: [
                                        ConstrainedBox(
                                          constraints: BoxConstraints(
                                            minHeight: constraints.maxHeight,
                                          ),
                                          child: IntrinsicHeight(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.stretch,
                                              children: [
                                                for (
                                                  var i = 0;
                                                  i < cards.length;
                                                  i++
                                                ) ...[
                                                  target(i),
                                                  LongPressDraggable<Object>(
                                                    data: cards[i],
                                                    feedback: Material(
                                                      elevation: 4,
                                                      child: SizedBox(
                                                        width: 240,
                                                        child: ListTile(
                                                          title: Text(
                                                            cards[i].text,
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                    childWhenDragging:
                                                        const SizedBox(
                                                          height: 48,
                                                        ),
                                                    child: Card(
                                                      child: ListTile(
                                                        title: Text(
                                                          cards[i].text,
                                                        ),
                                                        subtitle:
                                                            [
                                                              if (cards[i]
                                                                      .priority !=
                                                                  'normal')
                                                                cards[i]
                                                                    .priority,
                                                              if (cards[i]
                                                                      .due !=
                                                                  null)
                                                                cards[i].due!,
                                                            ].isEmpty
                                                            ? null
                                                            : Text(
                                                                [
                                                                  if (cards[i]
                                                                          .priority !=
                                                                      'normal')
                                                                    cards[i]
                                                                        .priority,
                                                                  if (cards[i]
                                                                          .due !=
                                                                      null)
                                                                    cards[i]
                                                                        .due!,
                                                                ].join(' · '),
                                                              ),
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                                for (final issue
                                                    in issues.where(
                                                      (i) => i.status == column,
                                                    ))
                                                  LongPressDraggable<Object>(
                                                    data: issue,
                                                    feedback: Material(
                                                      child: SizedBox(
                                                        width: 240,
                                                        child: ListTile(
                                                          title: Text(
                                                            issuePreview(
                                                              issue.text,
                                                            ),
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                    childWhenDragging:
                                                        const SizedBox(
                                                          height: 48,
                                                        ),
                                                    child: Card(
                                                      child: ListTile(
                                                        title: Text(
                                                          issuePreview(
                                                            issue.text,
                                                          ),
                                                        ),
                                                        subtitle: Wrap(
                                                          children: [
                                                            Chip(
                                                              avatar: Icon(
                                                                iconForKind(
                                                                  issue.marker,
                                                                ),
                                                              ),
                                                              label: Text(
                                                                issue.marker,
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                Expanded(
                                                  child: target(
                                                    cards.length,
                                                    fill: true,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                ],
              ),
            ),
    );
  }
}
