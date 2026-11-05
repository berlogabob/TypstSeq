import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:tylog_core/tylog_core.dart';

import '../vault.dart';
import '../github/github_client.dart';
import '../github/send_issue.dart';
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
    this.githubClient,
    this.onOpenUrl,
    this.boardId,
    this.embedded = false,
  });

  final String? boardId;
  final bool embedded;
  final Future<GitHubClient> Function()? githubClient;
  final void Function(String)? onOpenUrl;
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
  late final String id =
      widget.boardId ??
      base64Url.encode(utf8.encode(widget.entity.id)).replaceAll('=', '');
  late Board board = Board(
    id: id,
    title: widget.entity.title,
    scopeEntity: widget.entity.id,
  );
  late VaultIndex index = widget.index;
  bool loading = true;
  bool busy = false;
  bool loadFailed = false;
  List<Map<String, dynamic>> remoteIssues = [];

  String? get repo => board.extra['github_repo'] as String?;

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
        await _sync();
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
        final current = await readBoard(widget.vault.storage, id) ?? board;
        final next = Board.fromJson({
          ...current.toJson(),
          'schema': 2,
          'order': {...current.order, column: ordered},
        });
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
      var target = column;
      final repository = _repo(issue);
      if (issue.githubNumber != null) {
        if (repository == null ||
            widget.githubClient == null ||
            !['todo', 'doing', 'done'].contains(column)) {
          throw StateError(
            'GitHub issue requires a connection and a supported column',
          );
        }
        final client = await widget.githubClient!();
        final remote = await client.issue(repository, issue.githubNumber!);
        final current = _remoteColumn(remote);
        if (current != issue.status) {
          target = current;
          await _recordConflict(
            repository,
            issue.githubNumber!,
            current,
            'attempted $column from ${issue.status}',
          );
        } else {
          final labels = (remote['labels'] as List? ?? [])
              .whereType<Map>()
              .map((label) => label['name'])
              .whereType<String>()
              .toList();
          try {
            await client.updateIssueColumn(
              repository,
              issue.githubNumber!,
              column,
              labels,
              currentColumn: current,
            );
            final actual = await client.issue(repository, issue.githubNumber!);
            target = _remoteColumn(actual);
            if (target != column) {
              await _recordConflict(
                repository,
                issue.githubNumber!,
                target,
                'attempted $column; status changed during move',
              );
            }
          } catch (error) {
            final actual = await client.issue(repository, issue.githubNumber!);
            target = _remoteColumn(actual);
            await _recordConflict(
              repository,
              issue.githubNumber!,
              target,
              'move to $column failed: $error',
            );
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('GitHub move failed; refreshed: $error'),
                ),
              );
            }
          }
        }
      }
      if (!await widget.mutateNote(
        issue.notePath,
        (source) => setIssueStatus(source, issue, target),
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

  String? _repo(IssueRef issue) => issueGithubRepo(issue, index);

  Future<void> _send(IssueRef issue) async {
    final repo = _repo(issue);
    if (repo == null || widget.githubClient == null || busy) return;
    setState(() => busy = true);
    try {
      await sendIssueToGithub(
        issue: issue,
        repo: repo,
        vault: widget.vault,
        githubClient: widget.githubClient!,
        mutateNote: widget.mutateNote,
      );
      final next = await widget.refreshIndex();
      if (mounted && next != null) index = next;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not send issue: $e')));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _configureRepo() async {
    var input = repo ?? '';
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('GitHub repository'),
        content: TextFormField(
          initialValue: input,
          onChanged: (value) => input = value,
          decoration: const InputDecoration(labelText: 'owner/name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, input.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (value == null || !mounted) return;
    if (value.isNotEmpty &&
        !RegExp(r'^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$').hasMatch(value)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a repository as owner/name')),
      );
      return;
    }
    try {
      if (loadFailed) throw StateError('Board file could not be read');
      final current = await readBoard(widget.vault.storage, id) ?? board;
      final next = Board.fromJson({
        ...current.toJson(),
        'github_repo': value.isEmpty ? null : value,
      });
      await writeBoard(widget.vault.storage, next);
      widget.vault.restoreWriteMarkers(
        boardPath(id),
        stale: false,
        pendingSync: true,
      );
      if (!mounted) return;
      setState(() {
        board = next;
        remoteIssues = [];
      });
      await _sync();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save repository: $e')),
        );
      }
    }
  }

  String _remoteColumn(Map<String, dynamic> issue) {
    if (issue['state'] == 'closed') return 'done';
    final labels = issue['labels'] as List? ?? [];
    return labels.any((label) => label is Map && label['name'] == 'doing')
        ? 'doing'
        : 'todo';
  }

  Future<void> _dropRemote(Map<String, dynamic> shown, String column) async {
    final repository = repo;
    if (busy ||
        repository == null ||
        widget.githubClient == null ||
        !['todo', 'doing', 'done'].contains(column) ||
        _remoteColumn(shown) == column) {
      return;
    }
    setState(() => busy = true);
    try {
      final client = await widget.githubClient!();
      final number = (shown['number'] as num).toInt();
      final current = await client.issue(repository, number);
      if (_remoteColumn(current) != _remoteColumn(shown)) {
        await _recordConflict(
          repository,
          number,
          _remoteColumn(current),
          'attempted $column from ${_remoteColumn(shown)}',
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Issue changed on GitHub; GitHub version kept'),
            ),
          );
        }
      } else {
        final labels = (current['labels'] as List? ?? [])
            .whereType<Map>()
            .map((label) => label['name'])
            .whereType<String>()
            .toList();
        var updated = false;
        try {
          await client.updateIssueColumn(
            repository,
            number,
            column,
            labels,
            currentColumn: _remoteColumn(current),
          );
          updated = true;
          final actual = await client.issue(repository, number);
          if (mounted && repo == repository) {
            setState(
              () => remoteIssues = [
                for (final row in remoteIssues)
                  if (row['number'] == number) {...row, ...actual} else row,
              ],
            );
          }
          if (_remoteColumn(actual) != column) {
            await _recordConflict(
              repository,
              number,
              _remoteColumn(actual),
              'attempted $column; status changed during move',
            );
          }
        } catch (error) {
          Map<String, dynamic> actual;
          try {
            actual = await client.issue(repository, number);
          } catch (_) {
            final rows = await client.repositoryIssues(repository);
            actual = rows.firstWhere((row) => row['number'] == number);
            if (mounted && repo == repository) {
              setState(() => remoteIssues = rows);
            }
          }
          await _recordConflict(
            repository,
            number,
            _remoteColumn(actual),
            updated
                ? 'move to $column could not be verified individually: $error'
                : 'move to $column failed: $error',
          );
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('GitHub move refreshed: $error')),
            );
          }
        }
      }
      final rows = await client.repositoryIssues(repository);
      if (mounted && repo == repository) setState(() => remoteIssues = rows);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not update GitHub issue: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _recordConflict(
    String repository,
    int number,
    String target,
    String detail,
  ) async {
    await widget.vault.storage.createDirectory(decisionsDir);
    await widget.vault.storage.appendBytes(
      '$decisionsDir/github.jsonl',
      utf8.encode(
        encodeDecisions([
          Decision(
            at: DateTime.now().toIso8601String(),
            device: 'github',
            item: '$repository#$number',
            source: 'issue',
            action: 'seen',
            target: target,
            context: 'GitHub conflict: $detail; GitHub won',
          ),
        ]),
      ),
    );
  }

  Future<void> _sync() async {
    if (busy || widget.githubClient == null) return;
    final issues = issuesForEntity(
      widget.entity.id,
      index,
    ).where((i) => i.githubNumber != null && _repo(i) != null).toList();
    if (issues.isEmpty && repo == null) return;
    setState(() => busy = true);
    try {
      final client = await widget.githubClient!();
      if (repo != null) {
        final rows = await client.repositoryIssues(repo!);
        if (mounted) setState(() => remoteIssues = rows);
      }
      for (final issue in issues) {
        final repo = _repo(issue)!;
        final remote = await client.issue(repo, issue.githubNumber!);
        final column = _remoteColumn(remote);
        if (column != issue.status) {
          if (!await widget.mutateNote(
            issue.notePath,
            (s) => setIssueStatus(s, issue, column),
          )) {
            throw StateError('Issue could not be saved');
          }
          await _recordConflict(
            repo,
            issue.githubNumber!,
            column,
            'local status ${issue.status}',
          );
        }
      }
      final next = await widget.refreshIndex();
      if (mounted && next != null) index = next;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not sync GitHub issues: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tasks = tasksForEntity(widget.entity.id, index);
    final issues = issuesForEntity(widget.entity.id, index);
    final tasksByStatus = <String, List<TaskRef>>{};
    for (final task in tasks) {
      (tasksByStatus[task.status] ??= []).add(task);
    }
    final issuesByStatus = <String, List<IssueRef>>{};
    final linkedNumbers = <Object?>{};
    for (final issue in issues) {
      (issuesByStatus[issue.status] ??= []).add(issue);
      if (_repo(issue)?.toLowerCase() == repo?.toLowerCase()) {
        linkedNumbers.add(issue.githubNumber);
      }
    }
    final remoteByStatus = <String, List<Map<String, dynamic>>>{};
    for (final remote in remoteIssues) {
      if (!linkedNumbers.contains(remote['number'])) {
        (remoteByStatus[_remoteColumn(remote)] ??= []).add(remote);
      }
    }
    final columns = [
      ...board.columns.values,
      if (board.columns.showCancelled &&
          !board.columns.values.contains('cancelled'))
        'cancelled',
    ];
    return Scaffold(
      appBar: AppBar(
        title: widget.embedded
            ? null
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${widget.entity.title} Board',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (repo != null)
                    Text(
                      repo!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                ],
              ),
        actions: [
          if (widget.githubClient != null)
            IconButton(
              tooltip: 'GitHub repository',
              onPressed: busy || loading ? null : _configureRepo,
              icon: const Icon(Icons.settings),
            ),
          if (widget.githubClient != null)
            IconButton(
              tooltip: 'Sync with GitHub',
              onPressed: busy || loading ? null : _sync,
              icon: const Icon(Icons.sync),
            ),
        ],
      ),
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
                        final matching = tasksByStatus[column] ?? <TaskRef>[];
                        final orderedIds = board.orderCards(
                          column,
                          matching.map((t) => t.id),
                        );
                        final byId = <String, TaskRef>{};
                        for (final task in matching) {
                          byId.putIfAbsent(task.id, () => task);
                        }
                        final cards = [for (final id in orderedIds) byId[id]!];
                        final columnIssues =
                            issuesByStatus[column] ?? <IssueRef>[];
                        final columnRemote =
                            remoteByStatus[column] ?? <Map<String, dynamic>>[];
                        Widget target(int position, {bool fill = false}) =>
                            DragTarget<Object>(
                              onWillAcceptWithDetails: (_) => !busy,
                              onAcceptWithDetails: (details) {
                                final item = details.data;
                                if (item is TaskRef) {
                                  _drop(item, column, position, cards);
                                } else if (item is IssueRef) {
                                  _dropIssue(item, column);
                                } else if (item is Map<String, dynamic>) {
                                  _dropRemote(item, column);
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
                                  child: CustomScrollView(
                                    slivers: [
                                      SliverList.builder(
                                        itemCount:
                                            cards.length * 2 +
                                            columnIssues.length +
                                            columnRemote.length,
                                        itemBuilder: (context, itemIndex) {
                                          if (itemIndex < cards.length * 2) {
                                            final i = itemIndex ~/ 2;
                                            if (itemIndex.isEven)
                                              return target(i);
                                            return LongPressDraggable<Object>(
                                              data: cards[i],
                                              feedback: Material(
                                                elevation: 4,
                                                child: SizedBox(
                                                  width: 240,
                                                  child: ListTile(
                                                    title: Text(cards[i].text),
                                                  ),
                                                ),
                                              ),
                                              childWhenDragging: const SizedBox(
                                                height: 48,
                                              ),
                                              child: Card(
                                                child: ListTile(
                                                  title: Text(cards[i].text),
                                                  subtitle:
                                                      [
                                                        if (cards[i].priority !=
                                                            'normal')
                                                          cards[i].priority,
                                                        if (cards[i].due !=
                                                            null)
                                                          cards[i].due!,
                                                      ].isEmpty
                                                      ? null
                                                      : Text(
                                                          [
                                                            if (cards[i]
                                                                    .priority !=
                                                                'normal')
                                                              cards[i].priority,
                                                            if (cards[i].due !=
                                                                null)
                                                              cards[i].due!,
                                                          ].join(' · '),
                                                        ),
                                                ),
                                              ),
                                            );
                                          }
                                          final issueIndex =
                                              itemIndex - cards.length * 2;
                                          if (issueIndex <
                                              columnIssues.length) {
                                            final issue =
                                                columnIssues[issueIndex];
                                            return LongPressDraggable<Object>(
                                              data: issue,
                                              feedback: Material(
                                                child: SizedBox(
                                                  width: 240,
                                                  child: ListTile(
                                                    title: Text(
                                                      issuePreview(issue.text),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                              childWhenDragging: const SizedBox(
                                                height: 48,
                                              ),
                                              child: Card(
                                                child: ListTile(
                                                  title: Text(
                                                    issuePreview(issue.text),
                                                  ),
                                                  trailing:
                                                      issue.githubNumber ==
                                                              null &&
                                                          _repo(issue) !=
                                                              null &&
                                                          widget.githubClient !=
                                                              null
                                                      ? IconButton(
                                                          tooltip:
                                                              'Send to GitHub',
                                                          onPressed: busy
                                                              ? null
                                                              : () => _send(
                                                                  issue,
                                                                ),
                                                          icon: const Icon(
                                                            Icons.upload,
                                                          ),
                                                        )
                                                      : null,
                                                  subtitle: Wrap(
                                                    children: [
                                                      if (issue.githubNumber !=
                                                              null &&
                                                          _repo(issue) != null)
                                                        ActionChip(
                                                          label: Text(
                                                            '#${issue.githubNumber}',
                                                          ),
                                                          onPressed: () => widget
                                                              .onOpenUrl
                                                              ?.call(
                                                                'https://github.com/${_repo(issue)}/issues/${issue.githubNumber}',
                                                              ),
                                                        ),
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
                                            );
                                          }
                                          final remote =
                                              columnRemote[issueIndex -
                                                  columnIssues.length];
                                          return LongPressDraggable<Object>(
                                            data: remote,
                                            feedback: Material(
                                              child: SizedBox(
                                                width: 240,
                                                child: ListTile(
                                                  title: Text(
                                                    remote['title']
                                                            as String? ??
                                                        '',
                                                  ),
                                                ),
                                              ),
                                            ),
                                            childWhenDragging: const SizedBox(
                                              height: 48,
                                            ),
                                            child: Card(
                                              child: ListTile(
                                                title: Text(
                                                  remote['title'] as String? ??
                                                      '',
                                                ),
                                                subtitle: Text(
                                                  'GitHub #${remote['number']}',
                                                ),
                                                onTap: () => widget.onOpenUrl?.call(
                                                  'https://github.com/$repo/issues/${remote['number']}',
                                                ),
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                                      SliverFillRemaining(
                                        hasScrollBody: false,
                                        child: target(cards.length, fill: true),
                                      ),
                                    ],
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
