import 'dart:io';
import 'dart:typed_data';

import 'package:typst_flutter/typst_flutter.dart';

import 'vault_storage.dart';

export 'package:tylog_core/report.dart'
    show
        ReportFilter,
        generateReportSource,
        selectReportNotes,
        writeReportStorage;

class ReportPreparationException implements Exception {
  const ReportPreparationException(
    this.message, {
    this.attempts = 0,
    this.loadedPaths = const [],
  });

  final String message;
  final int attempts;
  final List<String> loadedPaths;

  @override
  String toString() => 'Report preparation failed: $message';
}

/// Compiles Typst [source] straight to PDF bytes, without writing anything.
///
/// [files] is the same virtual filesystem the preview hands the compiler — the
/// helper, note assets, vendored packages and bibliography — so what comes back
/// is byte-for-byte what Preview shows. Kept separate from
/// [exportReportPdfStorage] because that one exists to persist a report *into*
/// the vault; this one exists so a note can leave the app (the share sheet), and
/// on a SAF vault there is no file path to hand anyone anyway.
Future<Uint8List> compileSourcePdf({
  required String source,
  required Map<String, Uint8List> files,
}) async {
  final compiler = await TypstCompiler.create();
  try {
    final document = await compiler.compile(source: source, files: files);
    try {
      return await document.exportPdf();
    } finally {
      document.dispose();
    }
  } finally {
    compiler.dispose();
  }
}

Future<File> exportReportPdf(Directory root, File report) async {
  final path = report.absolute.path
      .substring(root.absolute.path.length + 1)
      .replaceAll(Platform.pathSeparator, '/');
  final output = await exportReportPdfStorage(LocalVaultStorage(root), path);
  return File('${root.path}/${output.path}');
}

/// Writes `<report>.pdf` next to the report source and also returns the bytes,
/// so a caller can hand them straight to the share sheet without re-reading
/// what it just wrote through SAF.
Future<
  ({
    String path,
    Uint8List bytes,
    List<String> loadedPaths,
    int loadedBytes,
    int attempts,
  })
>
exportReportPdfStorage(VaultStorage storage, String report) async {
  final virtual = <String, Uint8List>{};
  final loadedPaths = <String>{};
  var loadedBytes = 0;
  var attempts = 0;
  final source = await storage.readText(report);
  final compiler = await TypstCompiler.create();
  try {
    while (true) {
      attempts++;
      try {
        final document = await compiler.compile(source: source, files: virtual);
        await compiler.takeRequestedFiles();
        try {
          final output = '${report.substring(0, report.length - 4)}.pdf';
          final bytes = await document.exportPdf();
          await storage.writeBytes(output, bytes);
          return (
            path: output,
            bytes: bytes,
            loadedPaths: loadedPaths.toList()..sort(),
            loadedBytes: loadedBytes,
            attempts: attempts,
          );
        } finally {
          document.dispose();
        }
      } on TypstCompileException catch (error) {
        final requested = (await compiler.takeRequestedFiles()).toSet();
        final missing =
            requested.where((path) => !virtual.containsKey(path)).toList()
              ..sort();
        if (missing.isEmpty) {
          throw ReportPreparationException(
            error.toString(),
            attempts: attempts,
            loadedPaths: loadedPaths.toList()..sort(),
          );
        }
        for (final path in missing) {
          try {
            validateVaultPath(path);
            if (!await storage.exists(path)) {
              throw StateError('file does not exist');
            }
            final bytes = await storage.readBytes(path);
            virtual[path] = bytes;
            loadedPaths.add(path);
            loadedBytes += bytes.length;
          } catch (cause) {
            throw ReportPreparationException(
              '$path: $cause',
              attempts: attempts,
              loadedPaths: loadedPaths.toList()..sort(),
            );
          }
        }
      }
    }
  } finally {
    compiler.dispose();
  }
}
