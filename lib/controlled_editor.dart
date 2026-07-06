import 'package:flutter/services.dart';

enum MagicAction {
  noteLink,
  tag,
  task,
  date,
  project,
  citation,
  attachment,
  heading,
  bold,
  italic,
  table,
  equation,
  report,
}

String? deterministicTypstFix(String error, String source) {
  final match = RegExp(r'unknown variable:\s*([^\s]+)').firstMatch(error);
  if (match == null) return null;
  final word = match.group(1)!;
  if (!source.contains('#$word')) return null;
  return 'Typst treats #$word as code. Use $word for plain text, '
      r'\#'
      '$word for a literal hashtag, or #tylog.tag("$word") for a tag.';
}

class MagicRequest {
  const MagicRequest({
    required this.action,
    this.value,
    this.id,
    this.due,
    this.project,
    this.kind,
    this.rows = 2,
    this.columns = 2,
  });

  final MagicAction action;
  final String? value;
  final String? id;
  final String? due;
  final String? project;
  final String? kind;
  final int rows;
  final int columns;
}

class SourceEdit {
  const SourceEdit({required this.text, required this.selection});

  final String text;
  final TextSelection selection;
}

SourceEdit applyMagicEdit(
  String source,
  TextSelection selection,
  MagicRequest request,
) {
  final start = selection.isValid ? selection.start : source.length;
  final end = selection.isValid ? selection.end : source.length;
  final selected = source.substring(start, end);
  final value = request.value?.trim();
  final replacement = switch (request.action) {
    MagicAction.noteLink || MagicAction.project =>
      '#tylog.ref-note(${typstString(request.id ?? value ?? selected)})[${typstContent(selected.isEmpty ? value ?? '' : selected)}]',
    MagicAction.tag => '#tylog.tag(${typstString(value ?? selected)})',
    MagicAction.task => _taskSnippet(
      id: request.id ?? 'task',
      text: value ?? selected,
      due: request.due,
      project: request.project,
    ),
    MagicAction.date =>
      '#tylog.date-ref(${typstString(value ?? selected)})[${typstContent(selected.isEmpty ? value ?? '' : selected)}]',
    MagicAction.citation => '@${_citationKey(value ?? selected)}',
    MagicAction.attachment =>
      '#tylog.attachment(${typstString(value ?? '')}, kind: ${typstString(request.kind ?? 'file')})[${request.kind == 'image' ? '#image(${typstString(value ?? '')})' : typstContent(selected.isEmpty ? value?.split('/').last ?? '' : selected)}]',
    MagicAction.heading =>
      '= ${typstContent(selected.isEmpty ? value ?? 'Heading' : selected)}',
    MagicAction.bold => '#strong[${typstContent(selected)}]',
    MagicAction.italic => '#emph[${typstContent(selected)}]',
    MagicAction.table => _tableSnippet(request.rows, request.columns),
    MagicAction.equation => '\$${selected.isEmpty ? value ?? '' : selected}\$',
    MagicAction.report => '',
  };
  final text = source.replaceRange(start, end, replacement);
  return SourceEdit(
    text: text,
    selection: TextSelection.collapsed(offset: start + replacement.length),
  );
}

String _taskSnippet({
  required String id,
  required String text,
  String? due,
  String? project,
}) =>
    '#tylog.task(\n'
    '  id: ${typstString(id)},\n'
    '  text: ${typstString(text)},\n'
    '  due: ${due == null ? 'none' : typstString(due)},\n'
    '  project: ${project == null ? 'none' : typstString(project)},\n'
    ')';

String _tableSnippet(int rows, int columns) {
  final cells = List.filled(rows * columns, '[]').join(', ');
  return '#table(columns: $columns, $cells)';
}

String typstString(String value) =>
    '"${value.replaceAll(r'\', r'\\').replaceAll('"', r'\"')}"';

String typstContent(String value) => value.replaceAllMapped(
  RegExp(r'[\\#\[\]\$*_@]'),
  (match) => '\\${match.group(0)}',
);

String _citationKey(String value) {
  final key = value.trim();
  if (!RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(key)) {
    throw ArgumentError.value(value, 'value', 'Invalid citation key');
  }
  return key;
}
