import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'app_icons.dart';
import 'constants.dart';
import '../models.dart';
import '../controlled_editor.dart' show localTime;
import 'package:tylog_core/enrich.dart' show autoEntitiesMarker;
import 'package:tylog_core/tylog_core.dart' show attentionOf;
import 'ds/app_sheet.dart';

DateTime? screenshotCapturedAt(NoteRef note) =>
    DateTime.tryParse('${note.properties['captured_at'] ?? ''}')?.toLocal();

List<NoteRef> screenshotsOnDay(VaultIndex? index, String day) =>
    (index?.notes ?? const <NoteRef>[])
        .where((n) => n.kind == 'screenshot' && n.date == day)
        .toList()
      ..sort((a, b) {
        final first = screenshotCapturedAt(a);
        final second = screenshotCapturedAt(b);
        final order = first == null
            ? (second == null ? 0 : 1)
            : second == null
            ? -1
            : first.compareTo(second);
        return order == 0 ? a.path.compareTo(b.path) : order;
      });

/// Appends a user line above the generated entities block, never inside it.
String appendAboveAutoBlock(String source, String line) {
  final auto = source.indexOf(autoEntitiesMarker);
  if (auto < 0) return '${source.trimRight()}\n$line\n';
  return '${source.substring(0, auto).trimRight()}\n$line\n\n'
      '${source.substring(auto)}';
}

List<NoteRef> incomingOnDay(VaultIndex? index, String day) {
  final notes = (index?.notes ?? const <NoteRef>[]).where((note) {
    if (attentionOf(note) != 'new') return false;
    if (note.date == day) return true;
    if (note.kind != 'audio' || note.date != null) return false;
    final stamp = RegExp(r'^audio-(\d{8})-').firstMatch(note.id)?.group(1);
    if (stamp == null) return false;
    final derived =
        '${stamp.substring(0, 4)}-${stamp.substring(4, 6)}-${stamp.substring(6, 8)}';
    return derived == day;
  }).toList();
  notes.sort((a, b) {
    if (a.kind == 'screenshot' && b.kind != 'screenshot') return -1;
    if (a.kind != 'screenshot' && b.kind == 'screenshot') return 1;
    if (a.kind == 'screenshot') {
      final first = screenshotCapturedAt(a);
      final second = screenshotCapturedAt(b);
      final order = first == null
          ? (second == null ? 0 : 1)
          : second == null
          ? -1
          : first.compareTo(second);
      if (order != 0) return order;
    }
    return a.path.compareTo(b.path);
  });
  return notes;
}

String? screenshotAssetPath(NoteRef note) {
  final date = note.date;
  if (date == null ||
      !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(date) ||
      !RegExp(r'^shot-[a-f0-9]{16}$').hasMatch(note.id)) {
    return null;
  }
  return 'assets/screenshots/${date.substring(0, 4)}/${date.substring(5, 7)}/${note.id}.webp';
}

class ScreenshotThumbnail extends StatefulWidget {
  const ScreenshotThumbnail({
    super.key,
    required this.note,
    this.imageResolver,
    this.width = 72,
    this.height = 64,
  });
  final double? width;
  final double? height;
  final NoteRef note;
  final Future<Uint8List?> Function(String)? imageResolver;

  @override
  State<ScreenshotThumbnail> createState() => _ScreenshotThumbnailState();
}

class _ScreenshotThumbnailState extends State<ScreenshotThumbnail> {
  // Read once per asset: every sync/index update rebuilds the page, and a
  // fresh read each build blanked every thumbnail (the "flicker").
  String? _path;
  Future<Uint8List?>? _bytes;

  Future<Uint8List?>? _load() {
    final path = screenshotAssetPath(widget.note);
    if (path != _path || _bytes == null) {
      _path = path;
      _bytes = path == null ? null : widget.imageResolver?.call(path);
    }
    return _bytes;
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    width: widget.width,
    height: widget.height,
    child: FutureBuilder<Uint8List?>(
      future: _load(),
      builder: (context, snapshot) => snapshot.data == null
          ? const Icon(AppIcons.screenshot)
          : Image.memory(
              snapshot.data!,
              fit: BoxFit.cover,
              cacheWidth: 216,
              // A changed image keeps the old frame until the new decodes.
              gaplessPlayback: true,
              errorBuilder: (_, _, _) =>
                  const Icon(Icons.broken_image_outlined),
            ),
    ),
  );
}

class ScreenshotStrip extends StatelessWidget {
  const ScreenshotStrip({
    super.key,
    required this.index,
    required this.day,
    required this.onOpenPath,
    this.imageResolver,
    this.incoming = false,
    this.onDecide,
  });
  final VaultIndex? index;
  final String day;
  final ValueChanged<String> onOpenPath;
  final Future<Uint8List?> Function(String)? imageResolver;
  final bool incoming;
  final void Function(NoteRef note, String action)? onDecide;
  @override
  Widget build(BuildContext context) {
    final notes = incoming
        ? incomingOnDay(index, day)
        : screenshotsOnDay(index, day);
    if (notes.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(kSpace8),
          child: Text(
            '${incoming ? 'Incoming' : 'Screenshots'} (${notes.length})',
          ),
        ),
        SizedBox(
          height: 116,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              for (final note in notes)
                SizedBox(
                  // Tiles follow their screenshot when the list changes.
                  key: ValueKey(note.path),
                  width: 112,
                  child: InkWell(
                    onTap: () => onOpenPath(note.path),
                    onLongPress: incoming && onDecide != null
                        ? () async {
                            final action = await showModalBottomSheet<String>(
                              context: context,
                              builder: (context) => AppSheet(
                                title: note.title,
                                children: [
                                  for (final (label, value) in [
                                    ('Add to today', 'added-to-today'),
                                    ('Schedule…', 'scheduled'),
                                    ('Dismiss', 'dismissed'),
                                  ])
                                    ListTile(
                                      title: Text(label),
                                      onTap: () =>
                                          Navigator.pop(context, value),
                                    ),
                                ],
                              ),
                            );
                            if (action != null) onDecide!(note, action);
                          }
                        : null,
                    child: Column(
                      children: [
                        if (note.kind == 'screenshot')
                          ScreenshotThumbnail(
                            note: note,
                            imageResolver: imageResolver,
                          ),
                        if (note.kind == 'screenshot')
                          if (screenshotCapturedAt(note) case final time?)
                            Text(localTime(time)),
                        if (note.kind != 'screenshot')
                          Icon(
                            note.kind == 'audio'
                                ? Icons.mic
                                : Icons.lightbulb_outline,
                          ),
                        Text(
                          note.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
