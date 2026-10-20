import 'package:flutter/services.dart';
import 'package:unorm_dart/unorm_dart.dart' as unorm;

TextRange? findSearchRevealRange(
  String text,
  String query, {
  int? preferredOffset,
}) {
  final needle = unorm.nfc(query).toLowerCase();
  if (needle.isEmpty) return null;
  final normalized = unorm.nfc(text).toLowerCase();
  var normalizedStart = normalized.indexOf(needle);
  if (preferredOffset != null &&
      preferredOffset >= 0 &&
      preferredOffset < text.length) {
    final candidate = unorm.nfc(text.substring(preferredOffset)).toLowerCase();
    if (candidate.startsWith(needle)) {
      normalizedStart = _normalizedOffset(text, preferredOffset);
    }
  }
  if (normalizedStart < 0) return null;
  final start = _originalOffset(text, normalizedStart);
  final end = _originalOffset(text, normalizedStart + needle.length);
  return TextRange(start: start, end: end);
}

int _normalizedOffset(String text, int originalOffset) =>
    unorm.nfc(text.substring(0, originalOffset)).length;

int _originalOffset(String text, int normalizedOffset) {
  if (normalizedOffset <= 0) return 0;
  var original = 0;
  while (original < text.length &&
      unorm.nfc(text.substring(0, original)).length < normalizedOffset) {
    original++;
  }
  return original;
}
