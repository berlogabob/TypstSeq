import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'models.dart';
import 'scanner.dart';
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
    required this.termIds,
    required this.termFrequencies,
    this.overflowTermFrequencies,
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

  /// Frequencies keyed by the shared vocabulary id, packed by document.
  final Uint32List termIds;
  final Uint16List termFrequencies;
  final Map<int, int>? overflowTermFrequencies;
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

  int frequency(int term) {
    final overflow = overflowTermFrequencies?[term];
    if (overflow != null) return overflow;
    var low = 0;
    var high = termIds.length - 1;
    while (low <= high) {
      final middle = (low + high) ~/ 2;
      final value = termIds[middle];
      if (value == term) return termFrequencies[middle];
      if (value < term) {
        low = middle + 1;
      } else {
        high = middle - 1;
      }
    }
    return 0;
  }

  List<Object?> toJson(String key) => [
    key,
    id,
    path,
    title,
    kind,
    tags,
    aliases,
    {
      'ids': base64Encode(_typedBytes(termIds)),
      'frequencies': base64Encode(_typedBytes(termFrequencies)),
      if (overflowTermFrequencies != null)
        'overflow': [
          for (final entry in overflowTermFrequencies!.entries) entry.key,
          for (final entry in overflowTermFrequencies!.entries) entry.value,
        ],
    },
    fingerprint,
    contentHash,
    fileKind,
    status,
    snippet,
  ];

  factory _SearchDocument.fromJson(Object value) {
    final fields = (value as List).cast<Object?>();
    final packed = _decodeTermPairs(fields[7]);
    return _SearchDocument(
      id: fields[1] as String,
      path: fields[2] as String,
      title: fields[3] as String,
      kind: fields[4] as String,
      tags: stringList(fields[5]),
      aliases: stringList(fields[6]),
      termIds: packed.ids,
      termFrequencies: packed.frequencies,
      overflowTermFrequencies: packed.overflow,
      fingerprint: fields[8] as String?,
      contentHash: fields[9] as String?,
      fileKind: fields[10] as String?,
      status: fields[11] as String?,
      snippet: fields[12] as String?,
    );
  }
}

Uint8List _typedBytes(TypedData value) =>
    Uint8List.view(value.buffer, value.offsetInBytes, value.lengthInBytes);

class _PackedTerms {
  const _PackedTerms(this.ids, this.frequencies, this.overflow);

  final Uint32List ids;
  final Uint16List frequencies;
  final Map<int, int>? overflow;
}

class PkmsSearchIndex {
  PkmsSearchIndex._(this._documents, this._vocabulary) {
    _rebuildVocabularySearch();
    _rebuildPackedPostings();
  }

  final Map<String, _SearchDocument> _documents;
  List<String> _vocabulary;
  late Uint32List _vocabularyByName;
  List<String> _documentPaths = const [];
  Uint32List _postingStarts = Uint32List(0);
  List<int> _postingDocumentIds = const [];

  void _rebuildVocabularySearch() {
    final sorted = List<int>.generate(_vocabulary.length, (index) => index)
      ..sort((a, b) => _vocabulary[a].compareTo(_vocabulary[b]));
    _vocabularyByName = Uint32List.fromList(sorted);
  }

  int? _vocabularyIndex(String term) {
    var low = 0;
    var high = _vocabularyByName.length - 1;
    while (low <= high) {
      final middle = (low + high) ~/ 2;
      final index = _vocabularyByName[middle];
      final comparison = _vocabulary[index].compareTo(term);
      if (comparison == 0) return index;
      if (comparison < 0) {
        low = middle + 1;
      } else {
        high = middle - 1;
      }
    }
    return null;
  }

  void _rebuildPackedPostings() {
    _documentPaths = _documents.keys.toList(growable: false);
    final documentIds = <String, int>{
      for (var i = 0; i < _documentPaths.length; i++) _documentPaths[i]: i,
    };
    final counts = Uint32List(_vocabulary.length);
    for (final document in _documents.values) {
      for (final term in document.termIds) {
        counts[term]++;
      }
    }
    final starts = Uint32List(_vocabulary.length + 1);
    for (var i = 0; i < counts.length; i++) {
      starts[i + 1] = starts[i] + counts[i];
    }
    final List<int> postings = _documentPaths.length <= 0xffff
        ? Uint16List(starts.last)
        : Uint32List(starts.last);
    final next = Uint32List.fromList(starts.sublist(0, starts.length - 1));
    for (final entry in _documents.entries) {
      final documentId = documentIds[entry.key]!;
      for (final term in entry.value.termIds) {
        postings[next[term]++] = documentId;
      }
    }
    _postingStarts = starts;
    _postingDocumentIds = postings;
  }

  void _addPostings(int term, Set<int> target) {
    if (term < 0 || term >= _postingStarts.length - 1) return;
    for (var i = _postingStarts[term]; i < _postingStarts[term + 1]; i++) {
      target.add(_postingDocumentIds[i]);
    }
  }

  /// Lightweight, deterministic accounting for benchmark reports. This is a
  /// lower-bound estimate of retained Dart payload bytes, not VM heap usage.
  Map<String, int> get debugStats {
    int metadata = 0;
    int termPairs = 0;
    for (final document in _documents.values) {
      metadata +=
          _textBytes(document.id) +
          _textBytes(document.path) +
          _textBytes(document.title) +
          _textBytes(document.kind) +
          document.tags.fold<int>(0, (sum, value) => sum + _textBytes(value)) +
          document.aliases.fold<int>(
            0,
            (sum, value) => sum + _textBytes(value),
          ) +
          _textBytes(document.snippet);
      termPairs += document.termIds.length;
    }
    final int vocabularyBytes = _vocabulary.fold<int>(
      0,
      (sum, value) => sum + _textBytes(value),
    );
    final int compact = metadata + vocabularyBytes + termPairs * 12;
    final int legacy =
        metadata +
        vocabularyBytes +
        termPairs * 40 +
        _vocabulary.fold<int>(0, (sum, value) => sum + _textBytes(value));
    final postings = _postingDocumentIds.length;
    return {
      'notes': _documents.keys.where((key) => !_isDerivedKey(key)).length,
      'documents': _documents.length,
      'vocabulary': _vocabulary.length,
      'termPairs': termPairs,
      'postings': postings,
      'estimatedCompactBytes': compact,
      'estimatedLegacyBytes': legacy,
    };
  }

  static PkmsSearchIndex empty() => PkmsSearchIndex._({}, const []);

  void replaceWith(PkmsSearchIndex other) {
    _documents
      ..clear()
      ..addAll(other._documents);
    _vocabulary = other._vocabulary;
    _rebuildVocabularySearch();
    _rebuildPackedPostings();
  }

  static Future<PkmsSearchIndex> loadStorage(
    VaultStorage storage,
    String path,
  ) async {
    if (!await storage.exists(path)) return empty();
    try {
      final bytes = gzip.decode(await storage.readBytes(path));
      final json = jsonDecode(utf8.decode(bytes)) as Map<String, Object?>;
      if (json['version'] != 4) return empty();
      // The *derivation* the documents were built from, not the file format.
      // A document is cached against its note's content hash, so a derive-only
      // index bump — which changes tags without touching a byte of any note —
      // left every search document holding pre-fold spellings forever, and
      // tag-filtered search silently disagreed with the index it came from.
      // `version: 2` cannot catch that: it describes the envelope.
      if (json['indexVersion'] != kVaultIndexVersion) return empty();
      final vocabulary = (json['vocabulary'] as List).cast<String>();
      final documents = <String, _SearchDocument>{};
      for (final value in (json['documents'] as List)) {
        final fields = (value as List).cast<Object?>();
        final document = _SearchDocument.fromJson(fields);
        documents[fields[0] as String] = document;
        fields.fillRange(0, fields.length, null);
      }
      return PkmsSearchIndex._(documents, vocabulary);
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
    bool Function()? isCancelled,
  }) async {
    final documents = <String, _SearchDocument>{};
    final vocabulary = <String, int>{
      for (var i = 0; i < (previous?._vocabulary.length ?? 0); i++)
        previous!._vocabulary[i]: i,
    };
    int intern(String term) =>
        vocabulary.putIfAbsent(term, () => vocabulary.length);
    _PackedTerms terms(String text) => _packTermPairs(
      _frequencies(text).map((term, count) => MapEntry(intern(term), count)),
    );
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
      if (isCancelled?.call() ?? false) throw const IndexBuildCancelled();
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
      if (isCancelled?.call() ?? false) throw const IndexBuildCancelled();
      for (final result in results) {
        if (result.value != null) sources[result.key] = result.value!;
      }
      done += slice.length;
      onProgress?.call(done, total);
    }
    for (final note in misses) {
      final source = sources[note.path];
      if (source == null) continue;
      final packed = terms(
        '${note.id} ${note.title} ${note.aliases.join(' ')} ${note.tags.join(' ')} ${jsonEncode(note.properties)} $source',
      );
      documents[note.path] = _SearchDocument(
        id: note.id,
        path: note.path,
        title: note.title,
        kind: note.kind,
        tags: note.tags,
        aliases: note.aliases,
        termIds: packed.ids,
        termFrequencies: packed.frequencies,
        overflowTermFrequencies: packed.overflow,
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
      final packed = terms(
        '${task.id} ${task.text} ${task.project ?? ''} ${task.status} '
        '${task.priority} ${task.tags.join(' ')} ${task.assignees.join(' ')} '
        '${jsonEncode(task.properties)}',
      );
      documents['task:${task.id}'] = _SearchDocument(
        id: task.id,
        path: task.notePath,
        title: task.text,
        kind: 'task',
        tags: task.tags,
        aliases: task.assignees,
        termIds: packed.ids,
        termFrequencies: packed.frequencies,
        overflowTermFrequencies: packed.overflow,
        status: task.status,
        snippet: task.due ?? task.recurrence,
      );
    }
    for (final note in vault.notes) {
      for (final attachment in note.attachments) {
        documents.putIfAbsent('attachment:${attachment.path}', () {
          final packed = terms(
            '${attachment.path} ${attachment.title ?? ''} ${note.title}',
          );
          return _SearchDocument(
            id: attachment.path,
            path: attachment.path,
            title: attachment.title ?? attachment.path.split('/').last,
            kind: 'file',
            tags: note.tags,
            aliases: const [],
            termIds: packed.ids,
            termFrequencies: packed.frequencies,
            overflowTermFrequencies: packed.overflow,
            fileKind: attachment.kind,
          );
        });
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
    return PkmsSearchIndex._(
      documents,
      vocabulary.keys.toList(growable: false),
    );
  }

  Future<void> saveStorage(VaultStorage storage, String path) async {
    final data = utf8.encode(
      jsonEncode({
        'version': 4,
        'indexVersion': kVaultIndexVersion,
        'vocabulary': _vocabulary,
        'documents': [
          for (final path in (_documents.keys.toList()..sort()))
            _documents[path]!.toJson(path),
        ],
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
    final queryTokens = _tokens(query).toSet();
    final terms = queryTokens.map(_vocabularyIndex).whereType<int>().toSet();
    Set<int> candidates;
    if (queryTokens.isEmpty) {
      candidates = {for (var i = 0; i < _documentPaths.length; i++) i};
    } else {
      // ponytail: scan vocabulary for prefixes; add a prefix index if query latency warrants it.
      final lists = queryTokens.map((token) {
        final exact = _vocabularyIndex(token);
        final values = <int>{};
        if (exact != null) _addPostings(exact, values);
        for (var i = 0; i < _vocabulary.length; i++) {
          if (_vocabulary[i].startsWith(token)) _addPostings(i, values);
        }
        return values;
      });
      candidates = lists.any((values) => values.isEmpty)
          ? <int>{}
          : lists.skip(1).fold<Set<int>>({
              ...lists.first,
            }, (result, values) => result..retainAll(values));
    }
    final normalized = query.trim().toLowerCase();
    final results = <PkmsSearchResult>[];
    for (final documentId in candidates) {
      final path = _documentPaths[documentId];
      final document = _documents[path]!;
      if (tag != null && !document.tags.contains(tag)) continue;
      if (fileKind != null && document.fileKind != fileKind) continue;
      if (status != null && document.status != status) continue;
      var score = terms.fold<int>(
        0,
        (sum, term) => sum + document.frequency(term),
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

_PackedTerms _packTermPairs(Map<int, int> terms) {
  final entries = terms.entries.toList()
    ..sort((a, b) => a.key.compareTo(b.key));
  final ids = Uint32List(entries.length);
  final frequencies = Uint16List(entries.length);
  Map<int, int>? overflow;
  for (var i = 0; i < entries.length; i++) {
    final entry = entries[i];
    ids[i] = entry.key;
    if (entry.value > 0xffff) {
      (overflow ??= {})[entry.key] = entry.value;
      frequencies[i] = 0xffff;
    } else {
      frequencies[i] = entry.value;
    }
  }
  return _PackedTerms(ids, frequencies, overflow);
}

_PackedTerms _decodeTermPairs(Object? value) {
  if (value is Map) {
    final encoded = value.cast<String, Object?>();
    final overflowValue = encoded['overflow'];
    Map<int, int>? overflow;
    if (overflowValue is List) {
      final values = overflowValue.cast<Object?>();
      final midpoint = values.length ~/ 2;
      overflow = {
        for (var i = 0; i < midpoint; i++)
          (values[i] as num).toInt(): (values[midpoint + i] as num).toInt(),
      };
    }
    return _PackedTerms(
      _decodeUint32(encoded['ids'] as String),
      _decodeUint16(encoded['frequencies'] as String),
      overflow,
    );
  }
  final values = (value as List).cast<Object?>();
  final midpoint = values.length ~/ 2;
  return _packTermPairs({
    for (var i = 0; i < midpoint; i++)
      (values[i] as num).toInt(): (values[midpoint + i] as num).toInt(),
  });
}

Uint32List _decodeUint32(String encoded) {
  final bytes = Uint8List.fromList(base64Decode(encoded));
  return Uint32List.view(bytes.buffer);
}

Uint16List _decodeUint16(String encoded) {
  final bytes = Uint8List.fromList(base64Decode(encoded));
  return Uint16List.view(bytes.buffer);
}

int _textBytes(String? value) => value == null ? 0 : utf8.encode(value).length;
