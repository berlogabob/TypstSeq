import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'constants.dart';
import '../models.dart';
import '../controlled_editor.dart' show localTime;

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

String? screenshotAssetPath(NoteRef note) {
  final date = note.date;
  if (date == null ||
      !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(date) ||
      !RegExp(r'^shot-[a-f0-9]{16}$').hasMatch(note.id)) {
    return null;
  }
  return 'assets/screenshots/${date.substring(0, 4)}/${date.substring(5, 7)}/${note.id}.webp';
}

class ScreenshotThumbnail extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final path = screenshotAssetPath(note);
    return SizedBox(
      width: width,
      height: height,
      child: FutureBuilder<Uint8List?>(
        future: path == null ? null : imageResolver?.call(path),
        builder: (context, snapshot) => snapshot.data == null
            ? const Icon(Icons.screenshot_outlined)
            : Image.memory(
                snapshot.data!,
                fit: BoxFit.cover,
                cacheWidth: 216,
                errorBuilder: (_, _, _) =>
                    const Icon(Icons.broken_image_outlined),
              ),
      ),
    );
  }
}

class ScreenshotStrip extends StatelessWidget {
  const ScreenshotStrip({
    super.key,
    required this.index,
    required this.day,
    required this.onOpenPath,
    this.imageResolver,
  });
  final VaultIndex? index;
  final String day;
  final ValueChanged<String> onOpenPath;
  final Future<Uint8List?> Function(String)? imageResolver;
  @override
  Widget build(BuildContext context) {
    final notes = screenshotsOnDay(index, day);
    if (notes.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(kSpace8),
          child: Text('Screenshots (${notes.length})'),
        ),
        SizedBox(
          height: 116,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              for (final note in notes)
                SizedBox(
                  width: 112,
                  child: InkWell(
                    onTap: () => onOpenPath(note.path),
                    child: Column(
                      children: [
                        ScreenshotThumbnail(
                          note: note,
                          imageResolver: imageResolver,
                        ),
                        if (screenshotCapturedAt(note) case final time?)
                          Text(localTime(time)),
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
