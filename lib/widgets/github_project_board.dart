import 'package:flutter/material.dart';
import 'package:tylog_core/tylog_core.dart';
import '../github/github_client.dart';
import '../github/github_projects.dart';

class GitHubProjectBoard extends StatefulWidget {
  const GitHubProjectBoard({
    super.key,
    required this.board,
    required this.storage,
    required this.client,
    required this.deviceId,
  });
  final Board board;
  final VaultStorage storage;
  final Future<GitHubClient> Function() client;
  final String deviceId;
  @override
  State<GitHubProjectBoard> createState() => _GitHubProjectBoardState();
}

class _GitHubProjectBoardState extends State<GitHubProjectBoard> {
  late Future<ProjectBoard> future = load();
  bool busy = false;
  Future<ProjectBoard> load() async {
    final scope = widget.board.scopeExtra['github_project'] as Map;
    return GitHubProjects(await widget.client()).fetchProjectBoardFromGitHub(
      scope['owner'] as String,
      scope['number'] as int,
    );
  }

  Future<void> move(
    ProjectBoard board,
    ProjectItem item,
    ProjectColumn column,
  ) async {
    if (busy || item.status == column.id) return;
    final previous = item.status;
    setState(() {
      busy = true;
      item.status = column.id;
    });
    var moved = false;
    try {
      await GitHubProjects(
        await widget.client(),
      ).setProjectItemStatus(board.id, item.id, board.fieldId, column.id);
      moved = true;
      await widget.storage.createDirectory(decisionsDir);
      const path = '$decisionsDir/github.jsonl';
      final old = await widget.storage.exists(path)
          ? await widget.storage.readText(path)
          : '';
      await widget.storage.writeText(
        path,
        old +
            encodeDecisions([
              Decision(
                at: DateTime.now().toIso8601String(),
                device: widget.deviceId,
                item: item.id,
                source: 'github_project',
                action: 'status',
                target: column.name,
              ),
            ]),
      );
    } catch (error) {
      if (mounted) {
        if (!moved) setState(() => item.status = previous);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              moved
                  ? 'Moved card, but could not log decision: $error'
                  : 'Could not move card: $error',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.board.title),
      actions: [
        IconButton(
          onPressed: busy ? null : () => setState(() => future = load()),
          icon: const Icon(Icons.refresh),
          tooltip: 'Refresh',
        ),
      ],
    ),
    body: FutureBuilder<ProjectBoard>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Text('Could not load project: ${snapshot.error}'),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final board = snapshot.data!;
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final column in board.columns)
                SizedBox(
                  width: 260,
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          column.name,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Expanded(
                          child: DragTarget<ProjectItem>(
                            onWillAcceptWithDetails: (_) => !busy,
                            onAcceptWithDetails: (details) =>
                                move(board, details.data, column),
                            builder: (context, candidates, rejected) =>
                                Container(
                                  key: ValueKey('project-column-${column.id}'),
                                  color: candidates.isEmpty
                                      ? null
                                      : Theme.of(
                                          context,
                                        ).colorScheme.primaryContainer,
                                  child: ListView(
                                    children: [
                                      for (final item in board.items.where(
                                        (item) => item.status == column.id,
                                      ))
                                        LongPressDraggable<ProjectItem>(
                                          data: item,
                                          feedback: Material(
                                            child: SizedBox(
                                              width: 240,
                                              child: ListTile(
                                                title: Text(item.title),
                                              ),
                                            ),
                                          ),
                                          childWhenDragging: const SizedBox(
                                            height: 48,
                                          ),
                                          child: Card(
                                            child: ListTile(
                                              title: Text(item.title),
                                              subtitle: Text(
                                                [
                                                  if (item.number != null)
                                                    '#${item.number}',
                                                  if (item.repo != null)
                                                    item.repo!,
                                                ].join(' · '),
                                              ),
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
                ),
            ],
          ),
        );
      },
    ),
  );
}
