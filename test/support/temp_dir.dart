import 'dart:io';

/// Deletes a test temp dir, retrying while background workers (index,
/// enrichment, mounts) finish flushing files into it. A plain recursive
/// delete races them on CI ("Directory not empty").
Future<void> deleteTempDir(Directory dir) async {
  for (var i = 0; i < 10; i++) {
    try {
      if (await dir.exists()) await dir.delete(recursive: true);
      return;
    } on FileSystemException {
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
  }
}
