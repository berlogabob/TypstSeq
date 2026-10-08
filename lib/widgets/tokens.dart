import 'package:flutter/material.dart';

/// Spacing scale used throughout the UI.
/// Values are in dp.
class Space {
  /// 4dp spacing
  static const double x4 = 4.0;

  /// 8dp spacing
  static const double x8 = 8.0;

  /// 12dp spacing
  static const double x12 = 12.0;

  /// 16dp spacing
  static const double x16 = 16.0;

  /// 24dp spacing
  static const double x24 = 24.0;

  /// 18dp editor inset
  static const double editorInset = 18.0;
}

/// Corner radius scale used throughout the UI.
class Radii {
  /// Small radius (6dp)
  static const double small = 6.0;

  /// Medium radius (12dp)
  static const double medium = 12.0;

  /// Large radius (20dp)
  static const double large = 20.0;
}

/// Text size scale used throughout the UI.
class TextSize {
  /// Body large text size (for writing)
  static const double bodyLarge = 16.0;

  /// Body medium text size (for rows)
  static const double bodyMedium = 14.0;

  /// Body small text size (for secondary details)
  static const double bodySmall = 12.0;

  /// Label medium text size (for pills)
  static const double labelMedium = 12.0;

  /// Title small text size (for sections)
  static const double titleSmall = 14.0;

  /// Title large text size (for note/day headings)
  static const double titleLarge = 18.0;

  /// Headline small text size (for sheet headings)
  static const double headlineSmall = 20.0;
}

/// Motion durations used throughout the UI.
class Motion {
  /// 150ms dock motion
  static const Duration dock = Duration(milliseconds: 150);

  /// 200ms status transition
  static const Duration status = Duration(milliseconds: 200);

  /// 260ms graph zoom
  static const Duration graphZoom = Duration(milliseconds: 260);
}

/// Color roles used throughout the UI.
class ColorRoles {
  /// Primary color and on-primary color
  static const Color primary = Color(0xFF0B2F44);
  static const Color onPrimary = Color(0xFFFFFFFF);

  /// Surface color and on-surface color
  static const Color surface = Color(0xFFF8FAFC);
  static const Color onSurface = Color(0xFF000000);
  static const Color onSurfaceVariant = Color(0xFF3F414A);

  /// Container color and on-container color
  static const Color container = Color(0xFFE9F0F7);
  static const Color onContainer = Color(0xFF000000);

  /// Error color
  static const Color error = Color(0xFFB00000);
  static const Color onError = Color(0xFFFFFFFF);

  /// Warning color (amber)
  static const Color warning = Color(0xFFFFC107);
  static const Color onWarning = Color(0xFF000000);
}
