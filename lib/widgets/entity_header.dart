import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../models.dart';
import 'constants.dart';

/// A Logseq-style info card for an entity note (person/place/org…): avatar,
/// title + kind, aliases, and its `properties` (email tappable), shown above the
/// note body.
class EntityHeader extends StatelessWidget {
  const EntityHeader({
    super.key,
    required this.note,
    required this.onOpenUrl,
    this.imageResolver,
  });

  final NoteRef note;
  final void Function(String url) onOpenUrl;
  final Future<Uint8List?> Function(String path)? imageResolver;

  String? get _avatarPath => note.attachments
      .where((a) => a.kind == 'image')
      .map((a) => a.path)
      .firstOrNull;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final properties = note.properties.entries
        .where((e) => e.value != null && '${e.value}'.trim().isNotEmpty)
        .toList();
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 6),
      color: scheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _Avatar(
                  path: _avatarPath,
                  kind: note.kind,
                  imageResolver: imageResolver,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        note.title,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        note.kind,
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (note.aliases.isNotEmpty) ...[
              const SizedBox(height: 10),
              _Chips(icon: Icons.badge_outlined, labels: note.aliases),
            ],
            if (note.tags.isNotEmpty) ...[
              const SizedBox(height: 6),
              _Chips(icon: Icons.tag, labels: note.tags),
            ],
            for (final entry in properties)
              _PropertyRow(
                name: entry.key,
                value: '${entry.value}',
                onOpenUrl: onOpenUrl,
              ),
          ],
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.path, required this.kind, this.imageResolver});

  final String? path;
  final String kind;
  final Future<Uint8List?> Function(String path)? imageResolver;

  @override
  Widget build(BuildContext context) {
    final fallback = CircleAvatar(
      radius: 26,
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Icon(iconForKind(kind), size: 26),
    );
    if (path == null || imageResolver == null) return fallback;
    return FutureBuilder<Uint8List?>(
      future: imageResolver!(path!),
      builder: (context, snapshot) {
        final data = snapshot.data;
        if (data == null || data.isEmpty) return fallback;
        return CircleAvatar(radius: 26, backgroundImage: MemoryImage(data));
      },
    );
  }
}

class _Chips extends StatelessWidget {
  const _Chips({required this.icon, required this.labels});

  final IconData icon;
  final List<String> labels;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 6,
    runSpacing: 6,
    children: [
      for (final label in labels)
        Chip(
          avatar: Icon(icon, size: 16),
          label: Text(label),
          visualDensity: VisualDensity.compact,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
    ],
  );
}

class _PropertyRow extends StatelessWidget {
  const _PropertyRow({
    required this.name,
    required this.value,
    required this.onOpenUrl,
  });

  final String name;
  final String value;
  final void Function(String url) onOpenUrl;

  bool get _isEmail =>
      name.toLowerCase() == 'email' ||
      RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value);
  bool get _isUrl => RegExp(r'^https?://').hasMatch(value);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tappable = _isEmail || _isUrl;
    final valueWidget = Text(
      value,
      style: TextStyle(color: tappable ? scheme.primary : null),
    );
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            _isEmail
                ? Icons.alternate_email
                : _isUrl
                ? Icons.link
                : Icons.label_outline,
            size: 16,
            color: scheme.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 84,
            child: Text(
              name,
              style: Theme.of(context).textTheme.labelMedium
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
          Expanded(
            child: tappable
                ? InkWell(
                    onTap: () =>
                        onOpenUrl(_isEmail && !_isUrl ? 'mailto:$value' : value),
                    child: valueWidget,
                  )
                : valueWidget,
          ),
        ],
      ),
    );
  }
}
