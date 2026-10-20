import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:tylog_core/storage.dart' show writeFileAtomic;

/// What this device shows collapsed (images by asset path; later list
/// subtrees). View state only: it never touches note source and never syncs.
class FoldStore extends ChangeNotifier {
  FoldStore._(this._file, this._keys);

  // ponytail: one app-wide store set at startup; null (tests, before load)
  // means nothing is folded and no fold controls show. Widgets listen to
  // [current] so pictures built before the load pick the store up.
  static final current = ValueNotifier<FoldStore?>(null);
  static FoldStore? get instance => current.value;
  static set instance(FoldStore? store) => current.value = store;

  static Future<FoldStore> open(File file) async {
    var keys = <String>{};
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is List) keys = decoded.whereType<String>().toSet();
    } catch (_) {}
    return FoldStore._(file, keys);
  }

  final File _file;
  final Set<String> _keys;

  Future<void> _writes = Future.value();

  bool isFolded(String key) => _keys.contains(key);

  Future<void> toggle(String key) {
    if (!_keys.remove(key)) _keys.add(key);
    notifyListeners();
    // Chained so a later toggle's snapshot can never land before an earlier.
    return _writes = _writes
        .catchError((Object _) {})
        .then(
          (_) =>
              writeFileAtomic(_file, utf8.encode(jsonEncode(_keys.toList()))),
        );
  }
}
