import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/graph.dart';
import 'package:tylog/widgets/constants.dart';

// ---------------------------------------------------------------------------
// WCAG 2.1 relative luminance / contrast ratio, applied to the app's
// hardcoded, non-token colors (edge strokes, the warning color) so a future
// edit can't silently drop one below the non-text 3:1 floor the way the old
// `Colors.amber` warning and the pre-WP-08 edge palette did.
// ---------------------------------------------------------------------------

/// sRGB channel -> linear, per the WCAG 2.1 relative luminance formula.
double _linearize(double channel) =>
    channel <= 0.03928 ? channel / 12.92 : math.pow((channel + 0.055) / 1.055, 2.4).toDouble();

/// Relative luminance of [c] (0 = black, 1 = white).
///
/// Uses the floating-point `.r`/`.g`/`.b` component getters — already
/// normalized to 0..1 — rather than `.red`/`.green`/`.blue`/`.value`, which
/// this SDK deprecated when `Color` moved to wide-gamut floating-point
/// components. The rest of the app already relies on that same API surface
/// (`Color.withValues(alpha: ...)` throughout `lib/graph.dart`).
double _luminance(Color c) {
  final r = _linearize(c.r);
  final g = _linearize(c.g);
  final b = _linearize(c.b);
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}

/// WCAG contrast ratio between two colors, order-independent.
double _contrast(Color a, Color b) {
  final la = _luminance(a);
  final lb = _luminance(b);
  final lighter = math.max(la, lb);
  final darker = math.min(la, lb);
  return (lighter + 0.05) / (darker + 0.05);
}

void main() {
  // WCAG 2.1 non-text contrast minimum (1.4.11): graphical objects and UI
  // components need at least 3:1 against adjacent colors.
  const kMinNonTextContrast = 3.0;

  final lightScheme = tyLogColorScheme(Brightness.light);
  final darkScheme = tyLogColorScheme(Brightness.dark);

  test('warningColor clears 3:1 non-text contrast on both themes', () {
    expect(
      _contrast(warningColor(lightScheme), lightScheme.surface),
      greaterThanOrEqualTo(kMinNonTextContrast),
      reason: 'light warningColor must clear 3:1 on the light app surface',
    );
    expect(
      _contrast(warningColor(darkScheme), darkScheme.surface),
      greaterThanOrEqualTo(kMinNonTextContrast),
      reason: 'dark warningColor must clear 3:1 on the dark app surface',
    );
  });

  test('light-mode graph edge colors clear 3:1 on the light app surface', () {
    for (final kind in GraphEdgeKind.values) {
      expect(
        _contrast(edgeColor(kind, Brightness.light), lightScheme.surface),
        greaterThanOrEqualTo(kMinNonTextContrast),
        reason: 'light edge color for $kind must clear 3:1 on the app surface',
      );
    }
  });

  test('dark-mode graph edge colors clear 3:1 on the dark app surface', () {
    for (final kind in GraphEdgeKind.values) {
      expect(
        _contrast(edgeColor(kind, Brightness.dark), darkScheme.surface),
        greaterThanOrEqualTo(kMinNonTextContrast),
        reason: 'dark edge color for $kind must clear 3:1 on the app surface',
      );
    }
  });
}
