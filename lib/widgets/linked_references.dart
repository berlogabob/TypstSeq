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

  /// Excerpts per (path, targets). The bytes were already cached, but the
  /// *parse* was not: every row re-ran `mentionExcerpts`, which parses the
  /// whole referencing note, on every rebuild of this panel — so a hub note
  /// with 200 backlinks re-parsed 200 notes on every shell notify.
  final _excerpts = <String, Future<List<String>>>{};
  bool _expanded = true;

  Future<String> _source(String path) =>
      _sources.putIfAbsent(path, () => widget.readSource(path));

  Future<List<String>> _excerptsFor(String path) {
    final key = '$path\u0000${widget.targets.join('\u0000')}';
    return _excerpts.putIfAbsent(
      key,
      () async => mentionExcerpts(await _source(path), widget.targets),
    );
  }

  @override
  void didUpdateWidget(LinkedReferences old) {
    super.didUpdateWidget(old);
    // Targets change when the open note changes; its excerpts are keyed on
    // them, so stale entries would just accumulate.
    if (old.targets != widget.targets) _excerpts.clear();
  }

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
              child: ListView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.only(bottom: 8),
                itemCount: widget.backlinks.length,
                itemBuilder: (context, i) {
                  final path = widget.backlinks.elementAt(i);
                  return _Reference(
                    title: widget.index?.notesByPath[path]?.title ?? path,
                    kind: widget.index?.notesByPath[path]?.kind ?? 'note',
                    excerpts: _excerptsFor(path),
                    onOpen: () => widget.onOpenPath(path),
                  );
                },
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
    required this.excerpts,
    required this.onOpen,
  });

  final String title;
  final String kind;

  /// Already parsed and cached by the parent — see `_excerptsFor`.
  final Future<List<String>> excerpts;
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
            FutureBuilder<List<String>>(
              future: excerpts,
              builder: (context, snapshot) {
                final excerpts = snapshot.data ?? const <String>[];
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
