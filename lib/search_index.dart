import 'dart:convert';
import 'dart:io';

import 'models.dart';
import 'pkms_registry.dart';

class PkmsSearchResult {
  const PkmsSearchResult({
    required this.id,
    required this.path,
    required this.title,
    required this.kind,
    required this.tags,
    required this.score,
    this.snippet,
  });

  final String id;
  final String path;
  final String title;
  final String kind;
  final List<String> tags;
  final int score;
  final String? snippet;
}

class _SearchDocument {
  const _SearchDocument({
    required this.id,
    required this.path,
    required this.title,
    required this.kind,
    required this.tags,
    required this.aliases,
    required this.terms,
    this.fingerprint,
    this.fileKind,
    this.status,
    this.snippet,
  });

  final String id;
  final String path;
  final String title;
  final String kind;
  final List<String> tags;
  final List<String> aliases;
  final Map<String, int> terms;
  final String? fingerprint;
  final String? fileKind;
  final String? status;
  final String? snippet;

  Map<String, Object?> toJson() => {
    'id': id,
    'path': path,
    'title': title,
    'kind': kind,
    'tags': tags,
    'aliases': aliases,
    'terms': {for (final key in (terms.keys.toList()..sort())) key: terms[key]},
    'fingerprint': fingerprint,
    if (fileKind != null) 'fileKind': fileKind,
    if (status != null) 'status': status,
    if (snippet != null) 'snippet': snippet,
  };

  factory _SearchDocument.fromJson(Map<String, Object?> json) =>
      _SearchDocument(
        id: json['id'] as String,
        path: json['path'] as String,
        title: json['title'] as String,
        kind: json['kind'] as String,
        tags: _strings(json['tags']),
        aliases: _strings(json['aliases']),
        terms: (json['terms'] as Map).map<String, int>(
          (key, value) => MapEntry(key.toString(), (value as num).toInt()),
        ),
        fingerprint: json['fingerprint'] as String?,
        fileKind: json['fileKind'] as String?,
        status: json['status'] as String?,
        snippet: json['snippet'] as String?,
      );
}

class PkmsSearchIndex {
  PkmsSearchIndex._(this._documents) {
    for (final entry in _documents.entries) {
      for (final term in entry.value.terms.keys) {
        _postings.putIfAbsent(term, () => {}).add(entry.key);
      }
    }
  }

  final Map<String, _SearchDocument> _documents;
  final Map<String, Set<String>> _postings = {};

  static PkmsSearchIndex empty() => PkmsSearchIndex._({});

  void replaceWith(PkmsSearchIndex other) {
    _documents
      ..clear()
      ..addAll(other._documents);
    _postings
      ..clear()
      ..addAll({
        for (final entry in other._postings.entries)
          entry.key: {...entry.value},
      });
  }

  static Future<PkmsSearchIndex> load(File file) async {
    if (!await file.exists()) return empty();
    try {
      final bytes = gzip.decode(await file.readAsBytes());
      final json = jsonDecode(utf8.decode(bytes)) as Map<String, Object?>;
      if (json['version'] != 1) return empty();
      final documents = (json['documents'] as Map).map<String, _SearchDocument>(
        (key, value) => MapEntry(
          key.toString(),
          _SearchDocument.fromJson((value as Map).cast<String, Object?>()),
        ),
      );
      return PkmsSearchIndex._(documents);
    } catch (_) {
      return empty();
    }
  }

  static Future<PkmsSearchIndex> build(
    Directory root,
    VaultIndex vault,
    PkmsFileRegistry files, {
    PkmsSearchIndex? previous,
  }) async {
    final documents = <String, _SearchDocument>{};
    for (final note in vault.notes) {
      final cached = previous?._documents[note.path];
      if (cached?.fingerprint == note.fingerprint) {
        documents[note.path] = cached!;
        continue;
      }
      final source = await File('${root.path}/${note.path}').readAsString();
      documents[note.path] = _SearchDocument(
        id: note.id,
        path: note.path,
        title: note.title,
        kind: 'note',
        tags: note.tags,
        aliases: note.aliases,
        terms: _frequencies(
          '${note.id} ${note.title} ${note.aliases.join(' ')} ${note.tags.join(' ')} $source',
        ),
        fingerprint: note.fingerprint,
        snippet: _snippet(source),
      );
    }
    for (final file in files.files.values) {
      documents['file:${file.id}'] = _SearchDocument(
        id: file.id,
        path: file.path,
        title: file.displayTitle,
        kind: 'file',
        tags: file.tags,
        aliases: const [],
        terms: _frequencies(
          '${file.id} ${file.displayTitle} ${file.kind} ${file.status} ${file.tags.join(' ')} ${file.path}',
        ),
        fileKind: file.kind,
        status: file.status,
        snippet: file.path,
      );
    }
    return PkmsSearchIndex._(documents);
  }

  Future<void> save(File file) async {
    await file.parent.create(recursive: true);
    final data = utf8.encode(
      jsonEncode({
        'version': 1,
        'documents': {
          for (final path in (_documents.keys.toList()..sort()))
            path: _documents[path]!.toJson(),
        },
      }),
    );
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsBytes(gzip.encode(data), flush: true);
    if (await file.exists()) await file.delete();
    await tmp.rename(file.path);
  }

  List<PkmsSearchResult> search(
    String query, {
    String? tag,
    String? fileKind,
    String? status,
    int limit = 50,
  }) {
    final terms = _tokens(query).toSet();
    Set<String> candidates;
    if (terms.isEmpty) {
      candidates = _documents.keys.toSet();
    } else {
      final lists = terms.map((term) => _postings[term] ?? const <String>{});
      candidates = lists.isEmpty
          ? <String>{}
          : lists.skip(1).fold<Set<String>>({
              ...lists.first,
            }, (result, values) => result..retainAll(values));
    }
    final normalized = query.trim().toLowerCase();
    final results = <PkmsSearchResult>[];
    for (final path in candidates) {
      final document = _documents[path]!;
      if (tag != null && !document.tags.contains(tag)) continue;
      if (fileKind != null && document.fileKind != fileKind) continue;
      if (status != null && document.status != status) continue;
      var score = terms.fold<int>(
        0,
        (sum, term) => sum + (document.terms[term] ?? 0),
      );
      if (document.id.toLowerCase() == normalized) score += 1000;
      if (document.title.toLowerCase() == normalized) score += 800;
      if (document.aliases.any((value) => value.toLowerCase() == normalized)) {
        score += 600;
      }
      if (document.title.toLowerCase().startsWith(normalized)) score += 200;
      results.add(
        PkmsSearchResult(
          id: document.id,
          path: document.path,
          title: document.title,
          kind: document.kind,
          tags: document.tags,
          score: score,
          snippet: document.snippet,
        ),
      );
    }
    results.sort((a, b) {
      final score = b.score.compareTo(a.score);
      return score != 0 ? score : a.title.compareTo(b.title);
    });
    return results.take(limit).toList();
  }
}

String? _snippet(String source) {
  for (final line in source.split('\n')) {
    final value = line.trim();
    if (value.isEmpty || value.startsWith('#') || value.startsWith('=')) {
      continue;
    }
    return value.length > 120 ? '${value.substring(0, 120)}…' : value;
  }
  return null;
}

Map<String, int> _frequencies(String text) {
  final frequencies = <String, int>{};
  for (final term in _tokens(text)) {
    frequencies.update(term, (count) => count + 1, ifAbsent: () => 1);
  }
  return frequencies;
}

Iterable<String> _tokens(String text) => RegExp(
  r'[\p{L}\p{N}]+',
  unicode: true,
).allMatches(text.toLowerCase()).map((match) => match.group(0)!);

List<String> _strings(Object? value) =>
    (value as List? ?? const []).map((item) => item.toString()).toList();
