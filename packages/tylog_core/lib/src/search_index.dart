import 'dart:convert';
import 'dart:io';

import 'models.dart';
import 'storage.dart';

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
    final root = file.parent.parent;
    final path = file.absolute.path
        .substring(root.absolute.path.length + 1)
        .replaceAll(Platform.pathSeparator, '/');
    return loadStorage(LocalVaultStorage(root), path);
  }

  static Future<PkmsSearchIndex> loadStorage(
    VaultStorage storage,
    String path,
  ) async {
    if (!await storage.exists(path)) return empty();
    try {
      final bytes = gzip.decode(await storage.readBytes(path));
      final json = jsonDecode(utf8.decode(bytes)) as Map<String, Object?>;
      if (json['version'] != 2) return empty();
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
    VaultIndex vault, {
    PkmsSearchIndex? previous,
  }) => buildStorage(LocalVaultStorage(root), vault, previous: previous);

  static Future<PkmsSearchIndex> buildStorage(
    VaultStorage storage,
    VaultIndex vault, {
    PkmsSearchIndex? previous,
  }) async {
    final documents = <String, _SearchDocument>{};
    for (final note in vault.notes) {
      final cached = previous?._documents[note.path];
      if (cached?.fingerprint == note.fingerprint) {
        documents[note.path] = cached!;
        continue;
      }
      final source = await storage.readText(note.path);
      documents[note.path] = _SearchDocument(
        id: note.id,
        path: note.path,
        title: note.title,
        kind: note.kind,
        tags: note.tags,
        aliases: note.aliases,
        terms: _frequencies(
          '${note.id} ${note.title} ${note.aliases.join(' ')} ${note.tags.join(' ')} ${jsonEncode(note.properties)} $source',
        ),
        fingerprint: note.fingerprint,
        snippet: _snippet(source),
      );
    }
    for (final task in vault.tasks) {
      documents['task:${task.id}'] = _SearchDocument(
        id: task.id,
        path: task.notePath,
        title: task.text,
        kind: 'task',
        tags: task.tags,
        aliases: task.assignees,
        terms: _frequencies(
          '${task.id} ${task.text} ${task.project ?? ''} ${task.status} '
          '${task.priority} ${task.tags.join(' ')} ${task.assignees.join(' ')} '
          '${jsonEncode(task.properties)}',
        ),
        status: task.status,
        snippet: task.due ?? task.recurrence,
      );
    }
    for (final note in vault.notes) {
      for (final attachment in note.attachments) {
        documents.putIfAbsent(
          'attachment:${attachment.path}',
          () => _SearchDocument(
            id: attachment.path,
            path: attachment.path,
            title: attachment.title ?? attachment.path.split('/').last,
            kind: 'file',
            tags: note.tags,
            aliases: const [],
            terms: _frequencies(
              '${attachment.path} ${attachment.title ?? ''} ${note.title}',
            ),
            fileKind: attachment.kind,
          ),
        );
      }
    }
    return PkmsSearchIndex._(documents);
  }

  Future<void> save(File file) async {
    final root = file.parent.parent;
    final path = file.absolute.path
        .substring(root.absolute.path.length + 1)
        .replaceAll(Platform.pathSeparator, '/');
    await saveStorage(LocalVaultStorage(root), path);
  }

  Future<void> saveStorage(VaultStorage storage, String path) async {
    final data = utf8.encode(
      jsonEncode({
        'version': 2,
        'documents': {
          for (final path in (_documents.keys.toList()..sort()))
            path: _documents[path]!.toJson(),
        },
      }),
    );
    await storage.writeBytes(path, gzip.encode(data));
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
