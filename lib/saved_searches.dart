import 'dart:convert';

import 'package:tylog_core/storage.dart';

/// A saved search with a name, query, and optional tag/status filters.
class SavedSearch {
  const SavedSearch({
    required this.name,
    required this.query,
    this.tag,
    this.status,
  });

  final String name;
  final String query;
  final String? tag;
  final String? status;

  Map<String, Object?> toJson() => {
    'name': name,
    'query': query,
    if (tag != null) 'tag': tag,
    if (status != null) 'status': status,
  };

  factory SavedSearch.fromJson(Map<String, Object?> json) => SavedSearch(
    name: json['name'] as String? ?? 'Untitled',
    query: json['query'] as String? ?? '',
    tag: _castString(json['tag']),
    status: _castString(json['status']),
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SavedSearch &&
          runtimeType == other.runtimeType &&
          name == other.name &&
          query == other.query &&
          tag == other.tag &&
          status == other.status;

  @override
  int get hashCode =>
      name.hashCode ^ query.hashCode ^ (tag?.hashCode ?? 0) ^ (status?.hashCode ?? 0);
}

/// Manages persistence of saved searches to '_system/saved-searches.json'.
class SavedSearchStore {
  SavedSearchStore(this.storage);

  final VaultStorage storage;
  static const _path = '_system/saved-searches.json';
  static const _version = 1;

  /// Loads saved searches from storage. Returns an empty list if the file is
  /// missing or corrupt.
  Future<List<SavedSearch>> load() async {
    try {
      if (!await storage.exists(_path)) {
        return const [];
      }
      final text = await storage.readText(_path);
      final json = jsonDecode(text) as Map<String, Object?>;

      // Version gate for future schema changes.
      if (json['schema'] != _version) {
        return const [];
      }

      final searches = json['searches'] as List?;
      if (searches == null) return const [];

      return [
        for (final item in searches)
          if (item is Map<String, Object?>)
            SavedSearch.fromJson(item.cast<String, Object?>()),
      ];
    } catch (_) {
      return const [];
    }
  }

  /// Saves a list of searches to storage as JSON.
  Future<void> save(List<SavedSearch> searches) async {
    final data = {
      'schema': _version,
      'searches': [for (final search in searches) search.toJson()],
    };
    await storage.writeText(_path, jsonEncode(data));
  }
}

/// Defensively cast to String, returning null if the value is not a string.
String? _castString(Object? value) => value is String ? value : null;
