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
    if (relative.startsWith('_index/') || relative.startsWith('.tylog/')) {
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
      files: FileSource.bytes(virtual),
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
