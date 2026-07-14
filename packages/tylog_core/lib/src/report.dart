import 'models.dart';
import 'storage.dart';

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

#export.report(${_typstString(title)}, [
${notes.map((note) => '#include "/${note.path}"\n#pagebreak()').join('\n')}
${notes.any((note) => note.citations.isNotEmpty) ? '#bibliography("/_system/bibliography.yml")\n' : ''}])
''';

Future<String> writeReportStorage(
  VaultStorage storage,
  String title,
  VaultIndex index,
  ReportFilter filter,
) async {
  final safe = title.trim().replaceAll(RegExp(r'[\\/]'), '-');
  if (safe.isEmpty) throw ArgumentError('Report title is empty');
  final output = 'outputs/$safe.typ';
  await storage.writeText(
    output,
    generateReportSource(title, selectReportNotes(index, filter)),
  );
  return output;
}

String _typstString(String value) =>
    '"${value.replaceAll(r'\', r'\\').replaceAll('"', r'\"')}"';
