import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';

import 'app_icons.dart';
import '../calendar_feeds.dart' show googleCalendarTemplateUrl;
import '../models.dart';
import 'constants.dart';

/// A Logseq-style info card for an entity note (person/place/org…): avatar,
/// title + kind, aliases, and its `properties` (email tappable), shown above the
/// note body. Collapsed by default (title, kind, relationships and a Details
/// toggle) so the body stays on screen; aliases, tags and properties show when
/// expanded.
class EntityHeader extends StatefulWidget {
  const EntityHeader({
    super.key,
    required this.note,
    required this.onOpenUrl,
    this.imageResolver,
    this.onChangeKindIcon,
    this.onOpenBoard,
    this.onOpenTimeline,
    this.relationships,
    this.onGithubChanged,
    this.onFillInfo,
    this.onEditDetails,
  });

  /// Opens the one metadata editor (`key:: value` lines).
  final VoidCallback? onEditDetails;

  /// Requests a draft of this page from public sources (Incoming > Fill info).
  final VoidCallback? onFillInfo;
  final ValueChanged<String>? onGithubChanged;
  final Widget? relationships;
  final VoidCallback? onChangeKindIcon;
  final VoidCallback? onOpenBoard;
  final VoidCallback? onOpenTimeline;
  final NoteRef note;
  final void Function(String url) onOpenUrl;
  final Future<Uint8List?> Function(String path)? imageResolver;

  @override
  State<EntityHeader> createState() => _EntityHeaderState();
}

class _EntityHeaderState extends State<EntityHeader> {
  // ponytail: expanded state lives for the app session only; persist it per
  // page if people want it kept across restarts.
  static final _expandedIds = <String>{};

  NoteRef get note => widget.note;
  ValueChanged<String>? get onGithubChanged => widget.onGithubChanged;
  Widget? get relationships => widget.relationships;
  VoidCallback? get onChangeKindIcon => widget.onChangeKindIcon;
  VoidCallback? get onOpenBoard => widget.onOpenBoard;
  VoidCallback? get onOpenTimeline => widget.onOpenTimeline;
  VoidCallback? get onFillInfo => widget.onFillInfo;
  VoidCallback? get onEditDetails => widget.onEditDetails;
  void Function(String url) get onOpenUrl => widget.onOpenUrl;
  Future<Uint8List?> Function(String path)? get imageResolver =>
      widget.imageResolver;

  String? get _avatarPath => note.attachments
      .where((a) => a.kind == 'image')
      .map((a) => a.path)
      .firstOrNull;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final expanded = _expandedIds.contains(note.id);
    final calendarUrl = note.kind == 'event'
        ? googleCalendarTemplateUrl(note)
        : null;
    final tags = note.tags.where((tag) => tag != note.kind).toList();
    final properties = note.properties.entries
        .where(
          (e) =>
              e.key != 'part_of' &&
              e.key != 'github' &&
              e.value != null &&
              '${e.value}'.trim().isNotEmpty,
        )
        .toList();
    final detailCount =
        note.aliases.length +
        tags.length +
        properties.length +
        (note.kind == 'project' && onGithubChanged != null ? 1 : 0);
    return Card(
      margin: const EdgeInsets.fromLTRB(kSpace12, kSpace4, kSpace12, kSpace4),
      color: scheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: kSpace12,
          vertical: kSpace4,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final narrow = constraints.maxWidth < 600;
                // Narrow (phone): one row of icons with tooltips; labelled
                // buttons wrapped onto two lines on the P30.
                Widget action(
                  String key,
                  IconData icon,
                  String label,
                  VoidCallback onPressed,
                ) => narrow
                    ? IconButton(
                        key: Key(key),
                        tooltip: label,
                        onPressed: onPressed,
                        icon: Icon(icon),
                      )
                    : TextButton.icon(
                        key: Key(key),
                        onPressed: onPressed,
                        icon: Icon(icon),
                        label: Text(label),
                      );
                final actions = <Widget>[
                  if (onOpenTimeline != null)
                    action(
                      'entity-timeline',
                      Icons.timeline,
                      'Timeline',
                      onOpenTimeline!,
                    ),
                  if (onOpenBoard != null)
                    action(
                      'entity-board-button',
                      Icons.view_kanban_outlined,
                      'Board',
                      onOpenBoard!,
                    ),
                  if (onEditDetails != null)
                    IconButton(
                      key: const Key('entity-edit-details'),
                      tooltip: 'Edit details',
                      onPressed: onEditDetails,
                      icon: const Icon(Icons.edit_note),
                    ),
                  if (onFillInfo != null)
                    action(
                      'entity-fill-info',
                      Icons.auto_awesome_outlined,
                      'Fill info',
                      onFillInfo!,
                    ),
                  if (calendarUrl != null)
                    action(
                      'entity-google-calendar',
                      Icons.edit_calendar_outlined,
                      'Add to Google Calendar',
                      () => onOpenUrl(calendarUrl),
                    ),
                ];
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        IconButton(
                          tooltip: 'Change kind icon',
                          onPressed: onChangeKindIcon,
                          icon: _Avatar(
                            path: _avatarPath,
                            kind: note.kind,
                            imageResolver: imageResolver,
                          ),
                        ),
                        const SizedBox(width: kSpace8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                note.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                              Text(
                                labelForKind(note.kind),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.labelMedium
                                    ?.copyWith(color: scheme.onSurfaceVariant),
                              ),
                            ],
                          ),
                        ),
                        if (!narrow) ...actions,
                      ],
                    ),
                    if (narrow) Wrap(children: actions),
                  ],
                );
              },
            ),
            ?relationships,
            if (detailCount > 0)
              Row(
                children: [
                  if (detailCount > 0)
                    TextButton.icon(
                      key: const Key('entity-details-toggle'),
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                      ),
                      onPressed: () => setState(() {
                        if (!_expandedIds.remove(note.id)) {
                          _expandedIds.add(note.id);
                        }
                      }),
                      icon: Icon(
                        expanded ? Icons.expand_less : Icons.expand_more,
                      ),
                      label: Text(
                        expanded ? 'Hide details' : 'Details ($detailCount)',
                      ),
                    ),
                ],
              ),
            if (expanded && note.aliases.isNotEmpty) ...[
              const SizedBox(height: kSpace4),
              _Chips(icon: Icons.badge_outlined, labels: note.aliases),
            ],
            if (expanded && tags.isNotEmpty) ...[
              const SizedBox(height: kSpace4),
              _Chips(icon: Icons.tag, labels: tags),
            ],
            if (expanded && note.kind == 'project' && onGithubChanged != null)
              TextFormField(
                key: ValueKey('github-${note.id}'),
                initialValue: note.properties['github'] as String? ?? '',
                decoration: const InputDecoration(
                  labelText: 'GitHub repository (owner/repo)',
                ),
                onFieldSubmitted: onGithubChanged,
              ),
            if (expanded)
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
      radius: 20,
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Icon(iconForKind(kind), size: 20),
    );
    if (path == null || imageResolver == null) return fallback;
    return FutureBuilder<Uint8List?>(
      future: imageResolver!(path!),
      builder: (context, snapshot) {
        final data = snapshot.data;
        if (data == null || data.isEmpty) return fallback;
        final side = (40 * MediaQuery.devicePixelRatioOf(context)).round();
        return CircleAvatar(
          radius: 20,
          backgroundImage: ResizeImage(
            MemoryImage(data),
            width: side,
            height: side,
          ),
        );
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
      padding: const EdgeInsets.only(top: kSpace8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            _isEmail
                ? Icons.alternate_email
                : _isUrl
                ? AppIcons.link
                : Icons.label_outline,
            size: 16,
            color: scheme.onSurfaceVariant,
          ),
          const SizedBox(width: kSpace8),
          SizedBox(
            width: 84,
            child: Text(
              name,
              style: Theme.of(
                context,
              ).textTheme.labelMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
          Expanded(
            child: tappable
                ? InkWell(
                    onTap: () => onOpenUrl(
                      _isEmail && !_isUrl ? 'mailto:$value' : value,
                    ),
                    child: valueWidget,
                  )
                : valueWidget,
          ),
        ],
      ),
    );
  }
}
