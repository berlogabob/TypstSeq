import 'dart:convert';
import 'dart:io';

import 'models.dart';
import 'storage.dart';
import 'values.dart';

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
    this.contentHash,
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

  /// Content hash of the note this document was built from.
  ///
  /// The cache key. `fingerprint` is mtime+size and cannot serve: the scanner
  /// deliberately re-stamps it on every warm note (`scanner.dart`, "re-stamp
  /// the cheap gate"), so after any mtime churn — a sync, a restored index —
  /// the scanner correctly reused every note via its content hash while this
  /// index missed on all of them and re-read, re-tokenised and re-posted the
  /// entire vault. That was the "warm scan that still burns ten minutes".
  final String? contentHash;
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
    if (contentHash != null) 'contentHash': contentHash,
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
        tags: stringList(json['tags']),
        aliases: stringList(json['aliases']),
        terms: (json['terms'] as Map).map<String, int>(
          (key, value) => MapEntry(key.toString(), (value as num).toInt()),
        ),
        fingerprint: json['fingerprint'] as String?,
        contentHash: json['contentHash'] as String?,
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

  static Future<PkmsSearchIndex> loadStorage(
    VaultStorage storage,
    String path,
  ) async {
    if (!await storage.exists(path)) return empty();
    try {
      final bytes = gzip.decode(await storage.readBytes(path));
      final json = jsonDecode(utf8.decode(bytes)) as Map<String, Object?>;
      if (json['version'] != 2) return empty();
      // The *derivation* the documents were built from, not the file format.
      // A document is cached against its note's content hash, so a derive-only
      // index bump — which changes tags without touching a byte of any note —
      // left every search document holding pre-fold spellings forever, and
      // tag-filtered search silently disagreed with the index it came from.
      // `version: 2` cannot catch that: it describes the envelope.
      if (json['indexVersion'] != kVaultIndexVersion) return empty();
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

  /// Task and attachment documents, which derive from notes rather than being
  /// keyed by note path.
  static bool _isDerivedKey(String key) =>
      key.startsWith('task:') || key.startsWith('attachment:');

  static const _readConcurrency = 16;

  static Future<PkmsSearchIndex> buildStorage(
    VaultStorage storage,
    VaultIndex vault, {
    PkmsSearchIndex? previous,
    void Function(int done, int total)? onProgress,
  }) async {
    final documents = <String, _SearchDocument>{};
    final misses = <NoteRef>[];
    for (final note in vault.notes) {
      final cached = previous?._documents[note.path];
      // Content hash first: it survives the mtime re-stamping that the scanner
      // does to every warm note, so a sync that only moved timestamps no longer
      // invalidates the whole corpus. Falls back to the fingerprint for
      // documents written before the hash was persisted.
      final hit =
          cached != null &&
          (cached.contentHash != null && note.contentHash != null
              ? cached.contentHash == note.contentHash
              : cached.fingerprint == note.fingerprint);
      if (hit) {
        documents[note.path] = cached;
      } else {
        misses.add(note);
      }
    }
    final total = misses.length;
    final sources = <String, String>{};
    var done = 0;
    for (var i = 0; i < misses.length; i += _readConcurrency) {
      final end = i + _readConcurrency < misses.length
          ? i + _readConcurrency
          : misses.length;
      final slice = misses.sublist(i, end);
      final results = await Future.wait(
        slice.map((note) async {
          // A single unreadable file must not abort the whole search build —
          // skip it (it simply won't be searchable) rather than throwing.
          try {
            return MapEntry(note.path, await storage.readText(note.path));
          } catch (_) {
            return MapEntry(note.path, null);
          }
        }),
      );
      for (final result in results) {
        if (result.value != null) sources[result.key] = result.value!;
      }
      done += slice.length;
      onProgress?.call(done, total);
    }
    for (final note in misses) {
      final source = sources[note.path];
      if (source == null) continue;
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
        contentHash: note.contentHash,
        snippet: _snippet(source),
      );
    }
    // Task and attachment docs derive entirely from notes, so when every note
    // came from the cache they are provably identical to `previous`'s — and
    // rebuilding them meant re-tokenising 3,725 task docs on every rebuild only
    // to throw the result away at the identity check below.
    if (previous != null && misses.isEmpty) {
      final previousNoteDocs = previous._documents.keys
          .where((key) => !_isDerivedKey(key))
          .length;
      // Same note docs, all served from cache: a deletion shows up here as a
      // smaller count and falls through to a full rebuild.
      if (documents.length == previousNoteDocs) return previous;
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
    // Every note doc came from the cache and the document set (tasks and
    // attachments derive from those same unchanged notes) has the same keys:
    // this build is byte-identical to `previous`, so hand the caller back the
    // same instance. The identity is the caller's signal that re-encoding and
    // re-writing the index file can be skipped, and it avoids rebuilding the
    // posting sets in the constructor.
    if (previous != null &&
        misses.isEmpty &&
        documents.length == previous._documents.length &&
        documents.keys.every(previous._documents.containsKey)) {
      return previous;
    }
    return PkmsSearchIndex._(documents);
  }

  Future<void> saveStorage(VaultStorage storage, String path) async {
    final data = utf8.encode(
      jsonEncode({
        'version': 2,
        'indexVersion': kVaultIndexVersion,
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

  /// Prefix search over titles, ids, and aliases — used to power inline
  /// "@" mention autocomplete. Distinct from [search], which is a full-word
  /// index lookup: this matches on `startsWith`, case-insensitively, and
  /// ranks an exact title match above a title prefix above an alias/id
  /// prefix.
  List<PkmsSearchResult> searchPrefix(String prefix, {int limit = 8}) {
    final normalized = prefix.trim().toLowerCase();
    if (normalized.isEmpty) return const [];
    final results = <PkmsSearchResult>[];
    for (final document in _documents.values) {
      final title = document.title.toLowerCase();
      int score;
      if (title == normalized) {
        score = 1000;
      } else if (title.startsWith(normalized)) {
        score = 500;
      } else if (document.id.toLowerCase().startsWith(normalized) ||
          document.aliases.any(
            (alias) => alias.toLowerCase().startsWith(normalized),
          )) {
        score = 300;
      } else {
        continue;
      }
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
