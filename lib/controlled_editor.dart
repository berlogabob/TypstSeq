import 'package:flutter/services.dart';

enum ControlledBlockKind {
  heading,
  paragraph,
  list,
  task,
  table,
  equation,
  raw,
}

class ControlledBlock {
  const ControlledBlock({
    required this.start,
    required this.end,
    required this.source,
    required this.kind,
    required this.supported,
  });

  final int start;
  final int end;
  final String source;
  final ControlledBlockKind kind;
  final bool supported;
}

class ControlledDocument {
  const ControlledDocument({required this.source, required this.blocks});

  final String source;
  final List<ControlledBlock> blocks;

  String replaceBlock(int index, String replacement) {
    final block = blocks[index];
    return source.replaceRange(block.start, block.end, replacement);
  }
}

ControlledDocument parseControlledTypst(String source) {
  final bodyStart = _bodyStart(source);
  final blocks = <ControlledBlock>[];
  var start = bodyStart;
  for (final separator in RegExp(r'\n[ \t]*\n').allMatches(source, bodyStart)) {
    if (separator.start > start) {
      blocks.add(_block(source, start, separator.start));
    }
    start = separator.end;
  }
  if (start < source.length) blocks.add(_block(source, start, source.length));
  return ControlledDocument(source: source, blocks: blocks);
}

ControlledBlock _block(String source, int start, int end) {
  final raw = source.substring(start, end);
  final trimmed = raw.trimLeft();
  final kind = switch (trimmed) {
    String value when value.startsWith('#tylog.task(') =>
      ControlledBlockKind.task,
    String value when value.startsWith('#table(') => ControlledBlockKind.table,
    String value when value.startsWith(r'$') && value.endsWith(r'$') =>
      ControlledBlockKind.equation,
    String value when RegExp(r'^=+\s').hasMatch(value) =>
      ControlledBlockKind.heading,
    String value
        when RegExp(r'^(?:[-+] |\d+\. )', multiLine: true).hasMatch(value) =>
      ControlledBlockKind.list,
    _ => ControlledBlockKind.paragraph,
  };
  final supported =
      kind != ControlledBlockKind.paragraph ||
      !_unsupportedCode.hasMatch(_removeSupportedInline(raw));
  return ControlledBlock(
    start: start,
    end: end,
    source: raw,
    kind: supported ? kind : ControlledBlockKind.raw,
    supported: supported,
  );
}

final _unsupportedCode = RegExp(r'#');

String _removeSupportedInline(String value) => value.replaceAll(
  RegExp(
    r'#(?:strong|emph|image|link|cite|tylog\.(?:ref-note|tag|date-ref|attachment))\b',
  ),
  '',
);

int _bodyStart(String source) {
  final match = RegExp(
    r'#show\s*:\s*tylog\.note\.with\s*\(',
  ).firstMatch(source);
  if (match == null) return 0;
  final open = source.indexOf('(', match.start);
  final end = _balancedParenEnd(source, open);
  if (end == null) return 0;
  var cursor = end;
  while (cursor < source.length &&
      (source.codeUnitAt(cursor) == 10 || source.codeUnitAt(cursor) == 13)) {
    cursor++;
  }
  return cursor;
}

int? _balancedParenEnd(String source, int open) {
  var depth = 0;
  var inString = false;
  for (var i = open; i < source.length; i++) {
    final code = source.codeUnitAt(i);
    if (code == 34 && (i == 0 || source.codeUnitAt(i - 1) != 92)) {
      inString = !inString;
    }
    if (inString) continue;
    if (code == 40) depth++;
    if (code == 41 && --depth == 0) return i + 1;
  }
  return null;
}

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
