import 'package:flutter/material.dart';

import '../models.dart';
import '../scanner.dart';
import 'constants.dart';

class LinksPanel extends StatelessWidget {
  const LinksPanel({
    super.key,
    required this.current,
    required this.outgoing,
    required this.backlinks,
    required this.fileRefs,
    required this.index,
    required this.resolveLink,
    required this.onOpenLink,
    required this.onOpenPath,
    required this.onOpenFile,
    required this.onEditMetadata,
    this.dayItems = const [],
  });

  final String? current;
  final List<String> outgoing;
  final List<String> backlinks;
  final List<String> fileRefs;
  final List<CalendarItem> dayItems;
  final VaultIndex? index;
  final LinkResolution Function(String title) resolveLink;
  final ValueChanged<String> onOpenLink;
  final ValueChanged<String> onOpenPath;
  final ValueChanged<String> onOpenFile;
  final VoidCallback onEditMetadata;

  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surfaceContainerLow,
    child: ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Text('Context', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Text(current ?? '-', maxLines: 2, overflow: TextOverflow.ellipsis),
        TextButton.icon(
          onPressed: current == null ? null : onEditMetadata,
          icon: const Icon(Icons.tune),
          label: const Text('Edit metadata'),
        ),
        const Divider(height: 28),
        _SectionTitle('Outgoing'),
        if (outgoing.isEmpty) const _EmptyHint('No links from this page yet.'),
        for (final link in outgoing)
          Builder(
            builder: (context) {
              final resolved = resolveLink(link);
              final icon = switch (resolved.status) {
                LinkResolutionStatus.resolved => Icons.open_in_new,
                LinkResolutionStatus.ambiguous => Icons.error_outline,
                LinkResolutionStatus.unresolved => Icons.add,
              };
              final subtitle = switch (resolved.status) {
                LinkResolutionStatus.resolved => resolved.path!,
                LinkResolutionStatus.ambiguous => 'Ambiguous target',
                LinkResolutionStatus.unresolved => 'Unresolved',
              };
              return ListTile(
                dense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                title: Text(link),
                subtitle: Text(subtitle),
                trailing: Icon(icon),
                shape: RoundedRectangleBorder(borderRadius: listTileRadius),
                onTap: resolved.status == LinkResolutionStatus.ambiguous
                    ? null
                    : () => onOpenLink(link),
              );
            },
          ),
        const Divider(height: 28),
        _SectionTitle('Linked files'),
        if (fileRefs.isEmpty) const _EmptyHint('No linked files on this note.'),
        for (final path in fileRefs)
          ListTile(
            dense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 8),
            leading: const Icon(Icons.attach_file),
            title: Text(path.split('/').last),
            subtitle: Text(path),
            shape: RoundedRectangleBorder(borderRadius: listTileRadius),
            onTap: () => onOpenFile(path),
          ),
        if (dayItems.isNotEmpty) ...[
          const Divider(height: 28),
          _SectionTitle('On this day'),
          for (final item in dayItems)
            ListTile(
              dense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 8),
              leading: Icon(
                item.kind == CalendarItemKind.task
                    ? Icons.task_alt
                    : Icons.event,
              ),
              title: Text(
                item.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                item.notePath,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              shape: RoundedRectangleBorder(borderRadius: listTileRadius),
              onTap: () => onOpenPath(item.notePath),
            ),
        ],
        const Divider(height: 28),
        _SectionTitle('Backlinks'),
        if (backlinks.isEmpty)
          const _EmptyHint('Mention this page elsewhere and it appears here.'),
        for (final path in backlinks)
          ListTile(
            dense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 8),
            leading: const Icon(Icons.link),
            title: Text(
              index?.notesByPath[path]?.title ?? path,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(path, maxLines: 1, overflow: TextOverflow.ellipsis),
            shape: RoundedRectangleBorder(borderRadius: listTileRadius),
            onTap: () => onOpenPath(path),
          ),
      ],
    ),
  );
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) =>
      Text(text, style: Theme.of(context).textTheme.labelLarge);
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Text(text, style: Theme.of(context).textTheme.bodySmall),
  );
}
