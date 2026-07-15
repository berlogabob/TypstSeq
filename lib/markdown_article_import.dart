import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:tylog_core/models.dart';
import 'package:tylog_core/scanner.dart';
import 'package:tylog_core/storage.dart';
import 'package:typst_flutter/typst_flutter.dart';
import 'package:yaml/yaml.dart';

class MarkdownArticleDiagnostic {
  const MarkdownArticleDiagnostic({
    required this.code,
    required this.message,
    this.line,
  });

  final String code;
  final String message;
  final int? line;
}

class MarkdownArticleDraft {
  const MarkdownArticleDraft({
    required this.id,
    required this.title,
    required this.date,
    required this.tags,
    required this.aliases,
    required this.properties,
    required this.sourceHash,
    required this.typstSource,
    required this.diagnostics,
  });

  final String id;
  final String title;
  final String? date;
  final List<String> tags;
  final List<String> aliases;
  final Map<String, Object?> properties;
  final String sourceHash;
  final String typstSource;
  final List<MarkdownArticleDiagnostic> diagnostics;
}

typedef MarkdownBodyConverter =
    Future<MarkdownTypstResult> Function({
      required String markdown,
      required String title,
      String? baseUrl,
    });

Future<MarkdownArticleDraft> buildMarkdownArticleDraft({
  required List<int> bytes,
  required String sourceName,
  MarkdownBodyConverter? converter,
}) async {
  final diagnostics = <MarkdownArticleDiagnostic>[];
  final source = _decodeSource(bytes, sourceName);
  final parsed = _parseFrontmatter(source, sourceName);
  final metadata = parsed.metadata;
  final title =
      _firstText(metadata['title']) ??
      _firstHeading(parsed.markdown) ??
      _filenameTitle(sourceName);
  if (title.isEmpty) {
    throw FormatException('No article title found in $sourceName');
  }

  final tags = _stringList(metadata['tags'], stripHash: true);
  final aliases = _stringList(metadata['aliases']);
  final date = _canonicalDate(
    metadata['journal_day'] ?? metadata['date'] ?? metadata['created'],
  );
  if ((metadata['journal_day'] ?? metadata['date'] ?? metadata['created']) !=
          null &&
      date == null) {
    diagnostics.add(
      const MarkdownArticleDiagnostic(
        code: 'invalid-date',
        message: 'The source date could not be mapped to YYYY-MM-DD',
      ),
    );
  }

  final properties = <String, Object?>{};
  const canonicalKeys = {
    'title',
    'tags',
    'aliases',
    'journal_day',
    'date',
    'created',
    'type',
  };
  for (final entry in metadata.entries) {
    if (!canonicalKeys.contains(entry.key)) {
      properties[entry.key] = entry.value;
    }
  }
  final sourceType = _firstText(metadata['type']);
  if (sourceType != null && sourceType.toLowerCase() != 'article') {
    properties['source_type'] = sourceType;
    diagnostics.add(
      MarkdownArticleDiagnostic(
        code: 'source-type',
        message: 'Source type "$sourceType" was preserved; kind is article',
      ),
    );
  }

  final sourceHash = sha256.convert(utf8.encode(source)).toString();
  properties
    ..['import_format'] = 'markdown'
    ..['import_source_name'] = sourceName
    ..['import_sha256'] = sourceHash;
  final baseUrl = _firstText(metadata['url'])?.trim();
  final idBasis = baseUrl == null || baseUrl.isEmpty ? source : baseUrl;
  final idHash = sha256.convert(utf8.encode(idBasis)).toString();
  final nativeResult = await (converter ?? convertMarkdown)(
    markdown: parsed.markdown,
    title: title,
    baseUrl: baseUrl == null || baseUrl.isEmpty ? null : baseUrl,
  );
  diagnostics.addAll(
    nativeResult.diagnostics.map(
      (item) => MarkdownArticleDiagnostic(
        code: item.code,
        message: item.message,
        line: item.line?.toInt(),
      ),
    ),
  );

  final header = serializeNoteHeader(
    NoteMetadataDraft(
      id: 'md-${idHash.substring(0, 16)}',
      title: title,
      kind: 'article',
      date: date,
      tags: tags,
      aliases: aliases,
      properties: properties,
    ),
  );
  return MarkdownArticleDraft(
    id: 'md-${idHash.substring(0, 16)}',
    title: title,
    date: date,
    tags: tags,
    aliases: aliases,
    properties: properties,
    sourceHash: sourceHash,
    typstSource:
        '#import "/_system/tylog.typ" as tylog\n\n$header\n\n${nativeResult.typst}',
    diagnostics: diagnostics,
  );
}

enum MarkdownDuplicateKind { newArticle, unchanged, changed }

class MarkdownDuplicateMatch {
  const MarkdownDuplicateMatch(this.kind, [this.existing]);

  final MarkdownDuplicateKind kind;
  final NoteRef? existing;
}

MarkdownDuplicateMatch classifyMarkdownDuplicate(
  MarkdownArticleDraft draft,
  Iterable<NoteRef> articles,
) {
  final incomingUrl = _firstText(draft.properties['url'])?.trim();
  for (final article in articles) {
    final existingUrl = _firstText(article.properties['url'])?.trim();
    final sameUrl =
        incomingUrl != null &&
        incomingUrl.isNotEmpty &&
        existingUrl == incomingUrl;
    if (article.id != draft.id && !sameUrl) continue;
    final unchanged = article.properties['import_sha256'] == draft.sourceHash;
    return MarkdownDuplicateMatch(
      unchanged
          ? MarkdownDuplicateKind.unchanged
          : MarkdownDuplicateKind.changed,
      article,
    );
  }
  return const MarkdownDuplicateMatch(MarkdownDuplicateKind.newArticle);
}

Future<String> nextMarkdownArticlePath(
  VaultStorage storage,
  String title,
) async {
  final safe = title
      .trim()
      .replaceAll(RegExp(r'[\\/:*?"<>|]'), '-')
      .replaceAll(RegExp(r'\s+'), ' ');
  final base = safe.isEmpty ? 'Imported article' : safe;
  var path = 'articles/$base.typ';
  var suffix = 2;
  while (await storage.exists(path)) {
    path = 'articles/$base (${suffix++}).typ';
  }
  return path;
}

String _decodeSource(List<int> bytes, String sourceName) {
  try {
    var value = utf8.decode(bytes, allowMalformed: false);
    if (value.startsWith('\uFEFF')) value = value.substring(1);
    return value.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  } on FormatException catch (error) {
    throw FormatException('Invalid UTF-8 in $sourceName: ${error.message}');
  }
}

({Map<String, Object?> metadata, String markdown}) _parseFrontmatter(
  String source,
  String sourceName,
) {
  if (!source.startsWith('---\n')) {
    return (metadata: const {}, markdown: source);
  }
  final lines = source.split('\n');
  var closing = -1;
  for (var index = 1; index < lines.length; index++) {
    if (lines[index] == '---' || lines[index] == '...') {
      closing = index;
      break;
    }
  }
  if (closing < 0) {
    throw FormatException('Unclosed YAML frontmatter in $sourceName');
  }
  try {
    final yaml = loadYaml(lines.sublist(1, closing).join('\n'));
    if (yaml != null && yaml is! Map) {
      throw FormatException('YAML frontmatter must be a map in $sourceName');
    }
    final metadata = <String, Object?>{};
    if (yaml is Map) {
      for (final entry in yaml.entries) {
        metadata[entry.key.toString()] = _plainYaml(entry.value);
      }
    }
    return (
      metadata: metadata,
      markdown: lines
          .skip(closing + 1)
          .join('\n')
          .replaceFirst(RegExp(r'^\n+'), ''),
    );
  } on YamlException catch (error) {
    throw FormatException('Invalid YAML in $sourceName: ${error.message}');
  }
}

Object? _plainYaml(Object? value) => switch (value) {
  YamlMap() => {
    for (final entry in value.entries)
      entry.key.toString(): _plainYaml(entry.value),
  },
  Map() => {
    for (final entry in value.entries)
      entry.key.toString(): _plainYaml(entry.value),
  },
  YamlList() => value.map(_plainYaml).toList(),
  List() => value.map(_plainYaml).toList(),
  DateTime() => value.toIso8601String(),
  null || bool() || num() || String() => value,
  _ => value.toString(),
};

String? _firstText(Object? value) {
  if (value == null) return null;
  final text = value.toString().trim();
  return text.isEmpty ? null : text;
}

List<String> _stringList(Object? value, {bool stripHash = false}) {
  final values = value is Iterable && value is! String ? value : [value];
  return values
      .where((item) => item != null)
      .map((item) => item.toString().trim())
      .map((item) => stripHash ? item.replaceFirst(RegExp(r'^#+'), '') : item)
      .where((item) => item.isNotEmpty)
      .toSet()
      .toList();
}

String? _canonicalDate(Object? value) {
  final text = _firstText(value);
  if (text == null) return null;
  final compact = RegExp(r'^(\d{4})(\d{2})(\d{2})$').firstMatch(text);
  final candidate = compact == null
      ? text
      : '${compact[1]}-${compact[2]}-${compact[3]}';
  final parsed = DateTime.tryParse(candidate);
  if (parsed == null) return null;
  return '${parsed.year.toString().padLeft(4, '0')}-'
      '${parsed.month.toString().padLeft(2, '0')}-'
      '${parsed.day.toString().padLeft(2, '0')}';
}

String? _firstHeading(String markdown) {
  final match = RegExp(
    r'^#\s+(.+?)\s*#?$',
    multiLine: true,
  ).firstMatch(markdown);
  if (match == null) return null;
  var title = match.group(1)!.trim();
  title = title.replaceAllMapped(
    RegExp(r'!?(?:\[([^]]*)\])\([^)]*\)'),
    (m) => m[1] ?? '',
  );
  title = title.replaceAll(RegExp(r'[*_~`]'), '').trim();
  return title.isEmpty ? null : title;
}

String _filenameTitle(String sourceName) {
  final name = sourceName.split(RegExp(r'[/\\]')).last;
  return name
      .replaceFirst(RegExp(r'\.(?:md|markdown)$', caseSensitive: false), '')
      .trim();
}
