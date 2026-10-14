import 'package:unorm_dart/unorm_dart.dart' as unorm;

final _nfcCache = <String, String>{};

/// Avoids expensive normalization for paths containing only NFC-stable units.
String nfcPath(String s) {
  for (var i = 0; i < s.length; i++) {
    final unit = s.codeUnitAt(i);
    if (unit < 0x0300 ||
        (unit >= 0x0400 && unit <= 0x0482) ||
        (unit >= 0x048A && unit <= 0x04FF) ||
        (unit >= 0xAC00 && unit <= 0xD7A3)) {
      continue;
    }
    final cached = _nfcCache[s];
    if (cached != null) return cached;
    final normalized = unorm.nfc(s);
    _nfcCache[s] = normalized;
    if (_nfcCache.length > 50000) _nfcCache.clear();
    return normalized;
  }
  return s;
}
