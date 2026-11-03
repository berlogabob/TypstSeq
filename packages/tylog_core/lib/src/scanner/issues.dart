part of '../scanner.dart';

final _issueStatus = RegExp(
  r'#metadata\(\(\s*"tylog-issue-status"\s*:\s*"(todo|doing|done|cancelled)"\s*,?\s*\)\)',
);
final _issueGithub = RegExp(
  r'#metadata\(\(\s*"tylog-issue-gh"\s*:\s*(\d+)\s*,?\s*\)\)',
);
final _issueLink = RegExp(r'#tylog\.ref-note\("([^"\n]+)"\)(?:\[[^\]\n]*\])?');
final _issuePrefix = RegExp(
  r'^\s*(?:(?:\\-|[-+*]|\d+\.)\s+)?(?:\d{1,2}:\d{2}\s+)?',
);

int _issueCommentStart(String text) {
  var quoted = false;
  var escaped = false;
  for (var i = 0; i < text.length; i++) {
    final char = text[i];
    if (escaped) {
      escaped = false;
      continue;
    }
    if (char == r'\') {
      escaped = true;
      continue;
    }
    if (char == '"') {
      quoted = !quoted;
      continue;
    }
    if (!quoted && char == '/' && i + 1 < text.length && text[i + 1] == '/') {
      return i;
    }
  }
  return text.length;
}

/// Updates only the issue metadata, provided the indexed line is unchanged.
String setIssueStatus(String source, IssueRef line, String status) {
  if (!const {'todo', 'doing', 'done', 'cancelled'}.contains(status)) {
    throw ArgumentError.value(status, 'status');
  }
  return _setIssueMetadata(
    source,
    line,
    _issueStatus,
    '#metadata(("tylog-issue-status": "$status"))',
  );
}

String setIssueGithubNumber(String source, IssueRef line, int number) {
  if (number <= 0) throw ArgumentError.value(number, 'number');
  return _setIssueMetadata(
    source,
    line,
    _issueGithub,
    '#metadata(("tylog-issue-gh": $number))',
  );
}

String _setIssueMetadata(
  String source,
  IssueRef line,
  RegExp pattern,
  String metadata,
) {
  final lines = source.split('\n');
  if (line.line < 1 ||
      line.line > lines.length ||
      lines[line.line - 1] != line.text) {
    throw StateError('Issue line changed');
  }
  final text = lines[line.line - 1];
  final comment = _issueCommentStart(text);
  final code = text.substring(0, comment);
  final matches = pattern.allMatches(code).toList();
  if (matches.length > 1) throw StateError('Duplicate issue status');
  final status = pattern == _issueGithub ? _issueStatus.firstMatch(code) : null;
  lines[line.line - 1] = matches.isEmpty
      ? status != null
            ? text.replaceRange(status.end, status.end, ' $metadata')
            : comment < text.length
            ? '${code.trimRight()} $metadata ${text.substring(comment)}'
            : text.endsWith('\r')
            ? '${text.substring(0, text.length - 1)} $metadata\r'
            : '$text $metadata'
      : text.replaceRange(matches.single.start, matches.single.end, metadata);
  return lines.join('\n');
}

List<String> _issueCandidateLines(String source) {
  final lines = source.split('\n');
  return [
    for (var i = 0; i < lines.length; i++)
      if (_issueLink.hasMatch(lines[i])) '${i + 1}:${lines[i]}',
  ];
}

Future<List<IssueRef>> _scanIssues(
  VaultStorage storage,
  Map<String, List<String>> sources,
  Map<String, NoteRef> notes,
) async {
  final byName = <String, NoteRef>{};
  for (final note in notes.values) {
    for (final name in [note.id, note.title, ...note.aliases]) {
      byName.putIfAbsent(name, () => note);
    }
  }
  List<String>? configured;
  try {
    const shared = '_system/settings/ai.json';
    const local = '_system/settings/ai.local.json';
    final path = await storage.exists(local) ? local : shared;
    final settings = await storage.exists(path)
        ? jsonDecode(await storage.readText(path))
        : <String, Object?>{};
    final value = settings['tasks']?['enrich']?['markers'];
    if (value is List) configured = value.whereType<String>().toList();
  } catch (_) {
    // Missing or malformed settings use the same discovery default as enrich.
  }
  final counts = <String, int>{};
  final lastUsed = <String, String>{};
  final recent = DateTime.now().subtract(const Duration(days: 365));
  final recentDay =
      '${recent.year.toString().padLeft(4, '0')}-${recent.month.toString().padLeft(2, '0')}-${recent.day.toString().padLeft(2, '0')}';
  for (final entry in sources.entries) {
    if (!entry.key.startsWith('daily/')) {
      continue;
    }
    for (final candidate in entry.value) {
      final line = candidate.substring(candidate.indexOf(':') + 1);
      final prefix = _issuePrefix.firstMatch(line)!;
      final link = _issueLink.matchAsPrefix(line, prefix.end);
      if (link != null) {
        final id = byName[link[1]]?.id ?? link[1]!;
        final day = entry.key.split('/').last.replaceFirst('.typ', '');
        if (day.compareTo(lastUsed[id] ?? '') > 0) lastUsed[id] = day;
        if (line.substring(link.end).trim().isNotEmpty) {
          counts[id] = (counts[id] ?? 0) + 1;
        }
      }
    }
  }
  final discovered =
      counts.entries
          .where(
            (e) =>
                e.value >= 5 &&
                (lastUsed[e.key] ?? '').compareTo(recentDay) >= 0,
          )
          .toList()
        ..sort((a, b) => b.value.compareTo(a.value));
  final markers = configured == null
      ? discovered.take(12).map((e) => e.key).toList()
      : configured.map((name) => byName[name]?.id ?? name).toList();
  final issues = <IssueRef>[];
  for (final entry in sources.entries) {
    for (final candidate in entry.value) {
      final separator = candidate.indexOf(':');
      final lineNumber = int.parse(candidate.substring(0, separator));
      final text = candidate.substring(separator + 1);
      final links = _issueLink.allMatches(text).toList();
      final projects = <String>{};
      for (final link in links) {
        final note = byName[link[1]];
        if (note?.kind == 'project') projects.add(note!.id);
      }
      if (projects.isEmpty) continue;
      final found = <String>{};
      for (final link in links) {
        final id = byName[link[1]]?.id ?? link[1]!;
        if (markers.contains(id)) found.add(id);
      }
      final plain = text
          .substring(_issuePrefix.firstMatch(text)!.end)
          .toLowerCase();
      for (final id in markers) {
        final name = (byName[id]?.title ?? id).toLowerCase();
        if (name.length >= 3 &&
            plain.startsWith(name) &&
            (plain.length == name.length ||
                !RegExp(
                  r'[\p{L}\p{N}]',
                  unicode: true,
                ).hasMatch(plain[name.length]))) {
          found.add(id);
        }
      }
      for (final project in projects) {
        for (final marker in found) {
          issues.add(
            IssueRef(
              notePath: entry.key,
              line: lineNumber,
              text: text,
              projectId: project,
              marker: marker,
              githubNumber: int.tryParse(
                _issueGithub
                        .firstMatch(text.substring(0, _issueCommentStart(text)))
                        ?.group(1) ??
                    '',
              ),
              status:
                  _issueStatus.firstMatch(
                    text.substring(0, _issueCommentStart(text)),
                  )?[1] ??
                  'todo',
            ),
          );
        }
      }
    }
  }
  return issues;
}
