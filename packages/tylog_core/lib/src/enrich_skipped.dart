import 'dart:convert';

import 'enrich.dart';
import 'storage.dart';

/// Insertion order records age for both notes and their skipped card keys.
class EnrichSkipped {
  final Map<String, Set<String>> notes = {};

  static Future<EnrichSkipped> load(VaultStorage storage, String device) async {
    final result = EnrichSkipped();
    try {
      final json = jsonDecode(
        await storage.readText('$enrichSkippedDir/$device.json'),
      );
      if (json is! Map ||
          json.values.any((v) => v is! List || v.any((k) => k is! String))) {
        return result;
      }
      for (final entry in json.entries) {
        if (entry.key is! String) return EnrichSkipped();
        for (final key in entry.value as List) {
          result.skip(entry.key as String, key as String);
        }
      }
    } catch (_) {
      return EnrichSkipped();
    }
    return result;
  }

  void skip(String path, String key) {
    final keys = notes.remove(path) ?? <String>{};
    keys.remove(key);
    keys.add(key);
    while (keys.length > 200) {
      keys.remove(keys.first);
    }
    notes[path] = keys;
    while (notes.length > 500) {
      notes.remove(notes.keys.first);
    }
  }

  bool prune(String path, Set<String> validKeys) {
    final keys = notes[path];
    if (keys == null) return false;
    final before = keys.length;
    keys.removeWhere((key) => !validKeys.contains(key));
    if (keys.isEmpty) notes.remove(path);
    return before != keys.length;
  }

  String serialize() => jsonEncode({
    for (final entry in notes.entries) entry.key: entry.value.toList(),
  });
}
