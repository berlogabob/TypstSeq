import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'constants.dart';
import '../models.dart';
import 'screenshot_strip.dart';
import '../controlled_editor.dart' show localTime;

/// Section bodies of a screenshot note source: '== Description' and '== Text'
/// headings; Typst backslash escapes (\- \# \_ \* \\ etc.) are undone.
Map<String, String> screenshotSections(String source) {
  final lines = source.split('\n');
  final raw = <String, String>{};
  String? current;
  final buffer = <String>[];
  for (final line in lines) {
    if (line.startsWith('== ')) {
      if (current != null) {
        raw[current] = buffer.join('\n');
      }
      current = line.substring(3).trim();
      buffer.clear();
    } else if (current != null) {
      buffer.add(line);
    }
  }
  if (current != null) {
    raw[current] = buffer.join('\n');
  }
  final sections = <String, String>{};
  for (final entry in raw.entries) {
    final body = entry.value.trim();
    final unescaped = body.replaceAllMapped(
      RegExp(r'\\(.)'),
      (m) => m.group(1)!,
    );
    sections[entry.key] = unescaped;
  }
  return sections;
}

class ScreenshotView extends StatelessWidget {
  const ScreenshotView({
    super.key,
    required this.note,
    required this.source,
    required this.imageResolver,
    this.onEdit,
  });
  final NoteRef note;
  final String source;
  final Future<Uint8List?> Function(String path) imageResolver;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final details = _detailsChildren(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 720) {
          return Row(
            // Full height: the picture is the main item.
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                flex: 2,
                child: _ScreenshotPicture(
                  key: const ValueKey('screenshot-picture'),
                  note: note,
                  imageResolver: imageResolver,
                ),
              ),
              VerticalDivider(width: 1),
              Expanded(
                flex: 3,
                child: ListView(
                  padding: EdgeInsets.all(kSpace16),
                  children: details,
                ),
              ),
            ],
          );
        }
        return Stack(
          fit: StackFit.expand,
          children: [
            _ScreenshotPicture(
              key: const ValueKey('screenshot-picture'),
              note: note,
              imageResolver: imageResolver,
            ),
            DraggableScrollableSheet(
              key: const ValueKey('screenshot-details-sheet'),
              initialChildSize: 0.2,
              minChildSize: 0.12,
              maxChildSize: 0.9,
              snap: true,
              builder: (context, controller) {
                return Material(
                  color: scheme.surface,
                  elevation: 3,
                  borderRadius: BorderRadius.vertical(
                    top: Radius.circular(kRadiusSmall * 2),
                  ),
                  child: ListView(
                    controller: controller,
                    padding: EdgeInsets.all(kSpace16),
                    children: [
                      Center(
                        child: Container(
                          width: 32,
                          height: 4,
                          decoration: BoxDecoration(
                            color: scheme.outlineVariant,
                            borderRadius: BorderRadius.all(
                              Radius.circular(kRadiusSmall),
                            ),
                          ),
                        ),
                      ),
                      ...details,
                    ],
                  ),
                );
              },
            ),
          ],
        );
      },
    );
  }

  List<Widget> _detailsChildren(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final children = <Widget>[];

    final titleRow = Row(
      children: [
        Expanded(child: Text(note.title, style: textTheme.titleLarge)),
        if (onEdit != null)
          IconButton(
            tooltip: 'Edit',
            icon: const Icon(Icons.edit_outlined),
            onPressed: onEdit,
          ),
      ],
    );
    children.add(titleRow);

    final captured = screenshotCapturedAt(note);
    final sourceApp = note.properties['source_app'];
    final metaParts = <String>[];
    if (captured != null) {
      metaParts.add(localTime(captured));
    }
    if (sourceApp != null) {
      metaParts.add(sourceApp.toString());
    }
    if (metaParts.isNotEmpty) {
      children.add(
        Padding(
          padding: EdgeInsets.only(top: kSpace4),
          child: Text(
            metaParts.join(' · '),
            style: textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    final keywords = note.properties['keywords'];
    final chips = keywords is List
        ? keywords.whereType<String>().toList()
        : const <String>[];
    if (chips.isNotEmpty) {
      children.add(
        Wrap(
          spacing: kSpace4,
          runSpacing: kSpace4,
          children: [for (final k in chips) Chip(label: Text(k))],
        ),
      );
    }

    final sections = screenshotSections(source);
    for (final name in ['Description', 'Text']) {
      final body = sections[name];
      if (body == null || body.isEmpty) continue;
      children.add(
        Padding(
          padding: EdgeInsets.only(top: kSpace16),
          child: Text(name, style: textTheme.titleMedium),
        ),
      );
      children.add(SizedBox(height: kSpace8));
      children.add(SelectableText(body));
    }

    return children;
  }
}

/// Owns the image future so it is created exactly once and survives the many
/// page rebuilds that sync/index updates trigger.
class _ScreenshotPicture extends StatefulWidget {
  const _ScreenshotPicture({
    super.key,
    required this.note,
    required this.imageResolver,
  });
  final NoteRef note;
  final Future<Uint8List?> Function(String path) imageResolver;

  @override
  State<_ScreenshotPicture> createState() => _ScreenshotPictureState();
}

class _ScreenshotPictureState extends State<_ScreenshotPicture> {
  Future<Uint8List?>? _bytes;

  String? _path;

  void _load() {
    _path = screenshotAssetPath(widget.note);
    _bytes = _path == null ? null : widget.imageResolver(_path!);
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(_ScreenshotPicture old) {
    super.didUpdateWidget(old);
    // Same view reused for another screenshot: load its picture.
    if (screenshotAssetPath(widget.note) != _path) _load();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      color: scheme.surfaceContainerHighest,
      child: InteractiveViewer(
        maxScale: 5,
        child: FutureBuilder<Uint8List?>(
          future: _bytes,
          builder: (context, snapshot) {
            final bytes = snapshot.data;
            if (bytes == null) {
              return const Center(
                child: Icon(Icons.image_not_supported_outlined),
              );
            }
            return Image.memory(
              bytes,
              fit: BoxFit.contain,
              gaplessPlayback: true,
            );
          },
        ),
      ),
    );
  }
}
