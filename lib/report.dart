import 'dart:io';
import 'dart:typed_data';

import 'package:typst_flutter/typst_flutter.dart';

import 'controlled_editor.dart';
import 'models.dart';

class ReportFilter {
  const ReportFilter({
    this.project,
    this.from,
    this.to,
    this.kinds = const {},
    this.tags = const {},
    this.articleStatus,
    this.taskStatus,
  });

  final String? project;
  final String? from;
  final String? to;
  final Set<String> kinds;
  final Set<String> tags;
  final String? articleStatus;
  final String? taskStatus;
}

List<NoteRef> selectReportNotes(VaultIndex index, ReportFilter filter) {
  final taskPaths = filter.taskStatus == null
      ? const <String>{}
      : index.tasks
            .where((task) => task.status == filter.taskStatus)
            .map((task) => task.notePath)
            .toSet();
  return index.notes.where((note) {
    if (filter.project != null &&
        note.project != filter.project &&
        !note.outgoingLinks.contains(filter.project)) {
      return false;
    }
    if (filter.from != null &&
        (note.date == null || note.date!.compareTo(filter.from!) < 0)) {
      return false;
    }
    if (filter.to != null &&
        (note.date == null || note.date!.compareTo(filter.to!) > 0)) {
      return false;
    }
    if (filter.kinds.isNotEmpty && !filter.kinds.contains(note.kind)) {
      return false;
    }
    if (filter.tags.isNotEmpty && !note.tags.any(filter.tags.contains)) {
      return false;
    }
    if (filter.articleStatus != null &&
        note.properties['status'] != filter.articleStatus) {
      return false;
    }
    if (filter.taskStatus != null && !taskPaths.contains(note.path)) {
      return false;
    }
    return true;
  }).toList()..sort((a, b) {
    final byDate = (a.date ?? '').compareTo(b.date ?? '');
    return byDate != 0 ? byDate : a.path.compareTo(b.path);
  });
}

String generateReportSource(String title, List<NoteRef> notes) =>
    '''#import "/_system/export.typ" as export

#export.report(${typstString(title)}, [
${notes.map((note) => '#include "/${note.path}"\n#pagebreak()').join('\n')}
])
''';

Future<File> writeReport(
  Directory root,
  String title,
  VaultIndex index,
  ReportFilter filter,
) async {
  final safe = title.trim().replaceAll(RegExp(r'[\\/]'), '-');
  if (safe.isEmpty) throw ArgumentError('Report title is empty');
  final output = File('${root.path}/outputs/$safe.typ');
  await output.parent.create(recursive: true);
  final tmp = File('${output.path}.tmp');
  await tmp.writeAsString(
    generateReportSource(title, selectReportNotes(index, filter)),
    flush: true,
  );
  if (await output.exists()) await output.delete();
  await tmp.rename(output.path);
  return output;
}

Future<File> exportReportPdf(Directory root, File report) async {
  final virtual = <String, Uint8List>{};
  await for (final entity in root.list(recursive: true, followLinks: false)) {
    if (entity is! File || entity.path.endsWith('.tmp')) continue;
    final relative = entity.absolute.path
        .substring(root.absolute.path.length + 1)
        .replaceAll(Platform.pathSeparator, '/');
    if (relative.startsWith('_index/') || relative.startsWith('.tylog/')) {
      continue;
    }
    final bytes = await entity.readAsBytes();
    virtual[relative] = bytes;
    virtual['/$relative'] = bytes;
  }
  final compiler = await TypstCompiler.create();
  try {
    final document = await compiler.compile(
      source: await report.readAsString(),
      files: FileSource.bytes(virtual),
    );
    try {
      final output = File(
        '${report.path.substring(0, report.path.length - 4)}.pdf',
      );
      final tmp = File('${output.path}.tmp');
      await tmp.writeAsBytes(await document.exportPdf(), flush: true);
      if (await output.exists()) await output.delete();
      await tmp.rename(output.path);
      return output;
    } finally {
      document.dispose();
    }
  } finally {
    compiler.dispose();
  }
}
