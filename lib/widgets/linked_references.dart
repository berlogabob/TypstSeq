import 'package:flutter/material.dart';

import '../controlled_editor.dart' show mentionExcerpts;
import '../models.dart';
import 'constants.dart';

/// Logseq-style "Linked references": every note that mentions the current page,
/// each with the excerpt line(s) where the mention occurs. Backlink paths come
/// from `VaultIndex.backlinksByTarget`; excerpts are extracted lazily from each
/// referencing note's source. Self-bounding (collapsible header + a height-
/// capped internal scroll) so it sits below an `Expanded` editor.
class LinkedReferences extends StatefulWidget {
  const LinkedReferences({
    super.key,
    required this.backlinks,
    required this.index,
    required this.targets,
    required this.readSource,
    required this.onOpenPath,
  });

  final List<String> backlinks;
  final VaultIndex? index;

  /// The current page's identifiers (id / title / aliases), lowercased.
  final Set<String> targets;
  final Future<String> Function(String path) readSource;
  final ValueChanged<String> onOpenPath;

  @override
  State<LinkedReferences> createState() => _LinkedReferencesState();
}

class _LinkedReferencesState extends State<LinkedReferences> {
  final _sources = <String, Future<String>>{};
  bool _expanded = true;

  Future<String> _source(String path) =>
      _sources.putIfAbsent(path, () => widget.readSource(path));

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerLow,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Divider(height: 1),
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  const Icon(Icons.hub_outlined, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Linked references (${widget.backlinks.length})',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                  Icon(_expanded ? Icons.expand_more : Icons.chevron_right),
                ],
              ),
            ),
          ),
          if (_expanded)
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * 0.35,
              ),
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.only(bottom: 8),
                children: [
                  for (final path in widget.backlinks)
                    _Reference(
                      title: widget.index?.notesByPath[path]?.title ?? path,
                      kind: widget.index?.notesByPath[path]?.kind ?? 'note',
                      source: _source(path),
                      targets: widget.targets,
                      onOpen: () => widget.onOpenPath(path),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _Reference extends StatelessWidget {
  const _Reference({
    required this.title,
    required this.kind,
    required this.source,
    required this.targets,
    required this.onOpen,
  });

  final String title;
  final String kind;
  final Future<String> source;
  final Set<String> targets;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onOpen,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  iconForKind(kind),
                  size: 16,
                  color: scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            FutureBuilder<String>(
              future: source,
              builder: (context, snapshot) {
                final excerpts = snapshot.hasData
                    ? mentionExcerpts(snapshot.data!, targets)
                    : const <String>[];
                if (excerpts.isEmpty) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 2, left: 22),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final line in excerpts)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            line,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(color: scheme.onSurfaceVariant),
                          ),
                        ),
                    ],
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
