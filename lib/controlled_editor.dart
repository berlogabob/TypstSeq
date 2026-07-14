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
    _addBlocks(source, start, separator.start, blocks);
    start = separator.end;
  }
  _addBlocks(source, start, source.length, blocks);
  return ControlledDocument(source: source, blocks: blocks);
}

void _addBlocks(
  String source,
  int start,
  int end,
  List<ControlledBlock> blocks,
) {
  var cursor = start;
  while (cursor < end) {
    while (cursor < end && _isNewline(source.codeUnitAt(cursor))) {
      cursor++;
    }
    if (cursor >= end) break;

    final semanticEnd = _semanticBlockEnd(source, cursor, end);
    if (semanticEnd != null) {
      blocks.add(_block(source, cursor, semanticEnd));
      cursor = semanticEnd;
      continue;
    }

    var blockEnd = end;
    var nextLine = source.indexOf('\n', cursor);
    while (nextLine >= 0 && nextLine + 1 < end) {
      nextLine++;
      if (_semanticBlockEnd(source, nextLine, end) != null) {
        blockEnd = nextLine - 1;
        break;
      }
      nextLine = source.indexOf('\n', nextLine);
    }
    if (blockEnd > cursor) blocks.add(_block(source, cursor, blockEnd));
    cursor = blockEnd;
  }
}

int? _semanticBlockEnd(String source, int start, int limit) {
  var contentStart = start;
  while (contentStart < limit) {
    final code = source.codeUnitAt(contentStart);
    if (code != 32 && code != 9) break;
    contentStart++;
  }
  final lineEnd = source.indexOf('\n', contentStart);
  final boundedLineEnd = lineEnd < 0 || lineEnd > limit ? limit : lineEnd;
  final line = source.substring(contentStart, boundedLineEnd);

  if (RegExp(r'^=+\s').hasMatch(line) ||
      (line.startsWith(r'$') && line.endsWith(r'$'))) {
    return boundedLineEnd;
  }
  for (final prefix in const ['#tylog.task(', '#table(']) {
    if (!source.startsWith(prefix, contentStart)) continue;
    final open = source.indexOf('(', contentStart);
    final close = _balancedParenEnd(source, open);
    if (close != null && close <= limit) return close;
  }
  return null;
}

bool _isNewline(int code) => code == 10 || code == 13;

String controlledBlockPreview(ControlledBlock block) {
  final source = block.source.trim();
  return switch (block.kind) {
    ControlledBlockKind.heading => source.replaceFirst(RegExp(r'^=+\s*'), ''),
    ControlledBlockKind.list =>
      source
          .split('\n')
          .map(
            (line) => _inlinePreview(
              line.replaceFirst(RegExp(r'^(?:[-+] |\d+\. )'), '• '),
            ),
          )
          .join('\n'),
    ControlledBlockKind.task => _namedString(source, 'text') ?? 'Task',
    ControlledBlockKind.table => 'Table',
    ControlledBlockKind.equation =>
      source.length >= 2
          ? source.substring(1, source.length - 1).trim()
          : source,
    ControlledBlockKind.raw => 'Custom Typst block',
    ControlledBlockKind.paragraph => _inlinePreview(source),
  };
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
      kind != ControlledBlockKind.paragraph || _inlineCodeDelimited(raw);
  return ControlledBlock(
    start: start,
    end: end,
    source: raw,
    kind: supported ? kind : ControlledBlockKind.raw,
    supported: supported,
  );
}

/// A paragraph stays editable when every `#` in it starts a cleanly
/// delimited inline call; each such call becomes a protected inline atom.
bool _inlineCodeDelimited(String raw) {
  for (var i = 0; i < raw.length; i++) {
    final code = raw.codeUnitAt(i);
    if (code == 92) {
      i++;
      continue;
    }
    if (code != 35) continue;
    final end = inlineCallEnd(raw, i);
    if (end == null) return false;
    i = end - 1;
  }
  return true;
}

/// Exclusive end of an inline `#name.sub(...)[...]…` call starting at
/// [start], or null when it is not cleanly delimited. At least one `(...)`
/// or `[...]` group is required, so statements like `#show: …` or
/// `#import "…"` stay unsupported.
int? inlineCallEnd(String source, int start) {
  final name = RegExp(
    r'#[A-Za-z][A-Za-z0-9_-]*(?:\.[A-Za-z][A-Za-z0-9_-]*)*',
  ).matchAsPrefix(source, start);
  if (name == null) return null;
  var i = name.end;
  var groups = 0;
  if (i < source.length && source.codeUnitAt(i) == 40) {
    final close = _balancedParenEnd(source, i);
    if (close == null) return null;
    i = close;
    groups++;
  }
  while (i < source.length && source.codeUnitAt(i) == 91) {
    final close = _balancedSquareEnd(source, i);
    if (close == null) return null;
    i = close;
    groups++;
  }
  return groups == 0 ? null : i;
}

int? _balancedSquareEnd(String source, int open) {
  var depth = 0;
  for (var i = open; i < source.length; i++) {
    final code = source.codeUnitAt(i);
    if (code == 92) {
      i++;
      continue;
    }
    if (code == 91) depth++;
    if (code == 93 && --depth == 0) return i + 1;
  }
  return null;
}

String _inlinePreview(String source) {
  var value = source;
  for (final pattern in [
    RegExp(r'#tylog\.(?:ref-note|date-ref|attachment)\([^)]*\)\[([^\]]*)\]'),
    RegExp(r'#link\([^)]*\)\[([^\]]*)\]'),
    RegExp(r'#(?:strong|emph)\[([^\]]*)\]'),
    // Generic labelled call, e.g. #footnote[…] or #custom(...)[…].
    RegExp(r'#[A-Za-z][A-Za-z0-9_.-]*(?:\([^)]*\))?\[([^\]]*)\]'),
  ]) {
    value = value.replaceAllMapped(pattern, (match) => match.group(1)!);
  }
  value = value
      .replaceAllMapped(
        RegExp(r'#tylog\.tag\("((?:\\.|[^"])*)"\)'),
        (match) => _unescapeString(match.group(1)!),
      )
      .replaceAllMapped(
        RegExp(r'@([A-Za-z0-9_.:+-]+)'),
        (match) => match.group(1)!,
      )
      .replaceAllMapped(RegExp(r'#cite\(([^)]*)\)'), (match) => match.group(1)!)
      .replaceAll(RegExp(r'#image\([^)]*\)'), 'Image')
      .replaceAllMapped(
        RegExp(r'\\([\\#\[\]\$*_@])'),
        (match) => match.group(1)!,
      );
  return value;
}

String? _namedString(String source, String name) {
  final match = RegExp('$name\\s*:\\s*"((?:\\\\.|[^"])*)"').firstMatch(source);
  return match == null ? null : _unescapeString(match.group(1)!);
}

String _unescapeString(String value) =>
    value.replaceAll(r'\"', '"').replaceAll(r'\\', r'\');

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
  mention,
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
    MagicAction.mention =>
      '#tylog.ref-note(${typstString(request.id ?? value ?? selected)})[${typstContent('@${value ?? selected}')}]',
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
      '= ${typstContent(selected.isEmpty ? value ?? '' : selected)}',
    MagicAction.bold => '#strong[${typstContent(selected)}]',
    MagicAction.italic => '#emph[${typstContent(selected)}]',
    MagicAction.table => _tableSnippet(request.rows, request.columns),
    MagicAction.equation => '\$${selected.isEmpty ? value ?? '' : selected}\$',
    MagicAction.report => '',
  };
  if (const {
    MagicAction.task,
    MagicAction.table,
    MagicAction.equation,
    MagicAction.heading,
  }.contains(request.action)) {
    final before = source.substring(0, start);
    final after = source.substring(end).replaceFirst(RegExp(r'^\n+'), '');
    final prefix = before.isEmpty
        ? ''
        : before.endsWith('\n\n')
        ? ''
        : before.endsWith('\n')
        ? '\n'
        : '\n\n';
    final inserted = '$prefix$replacement\n\n';
    return SourceEdit(
      text: '$before$inserted$after',
      selection: TextSelection.collapsed(
        offset:
            start +
            inserted.length -
            (request.action == MagicAction.heading ? 2 : 0),
      ),
    );
  }
  final text = source.replaceRange(start, end, replacement);
  final offset = switch (request.action) {
    MagicAction.bold when selected.isEmpty => start + '#strong['.length,
    MagicAction.italic when selected.isEmpty => start + '#emph['.length,
    _ => start + replacement.length,
  };
  return SourceEdit(
    text: text,
    selection: TextSelection.collapsed(offset: offset),
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
