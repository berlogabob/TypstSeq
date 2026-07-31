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
  return File('${root.path}/$output');
}

Future<String> exportReportPdfStorage(
  VaultStorage storage,
  String report,
) async {
  final virtual = <String, Uint8List>{};
  for (final entity in await storage.list(recursive: true)) {
    if (entity.isDirectory || entity.path.endsWith('.tmp')) continue;
    final relative = entity.path;
    if (relative.startsWith('_index/') ||
        // TylogVaultPaths.indexDonors: index caches, megabytes each, and never
        // referenced by a report.
        relative.startsWith('_system/index/') ||
        relative.startsWith('.tylog/')) {
      continue;
    }
    final bytes = await storage.readBytes(relative);
    virtual[relative] = bytes;
    virtual['/$relative'] = bytes;
  }
  final compiler = await TypstCompiler.create();
  try {
    final document = await compiler.compile(
      source: await storage.readText(report),
      files: virtual,
    );
    try {
      final output = '${report.substring(0, report.length - 4)}.pdf';
      await storage.writeBytes(output, await document.exportPdf());
      return output;
    } finally {
      document.dispose();
    }
  } finally {
    compiler.dispose();
  }
}
