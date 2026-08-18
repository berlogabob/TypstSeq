import 'package:flutter/material.dart';

// ---------------------------------------------------------------------------
// Design tokens
//
// Single source of truth for values the UI used to decide per-widget. Before
// this file the brand seed appeared in three places, seven different corner
// radii were in use, and "warning" was a raw `Colors.amber` that failed WCAG
// non-text contrast at 1.56:1. Anything visual and repeated belongs here so a
// change lands everywhere at once — `test/design_tokens_test.dart` and
// `test/contrast_test.dart` keep it that way.
// ---------------------------------------------------------------------------

/// The one brand seed both color schemes are derived from.
const kSeedColor = Color(0xFF0B2F44);

/// Light-theme surface overrides. Kept explicit (rather than the tone M3
/// picks) because the paper-white reading surface is a deliberate choice;
/// `onSurfaceVariant`/hint are darkened from the generated tones to clear 4.5:1.
const kLightSurface = Color(0xFFF8FAFC);
const kLightOnSurfaceVariant = Color(0xFF3F414A);
const kLightHint = Color(0xFF5F616A);

/// The app's color scheme for [brightness]. Reading mode's night theme uses the
/// dark variant of this rather than re-seeding its own scheme, so a brand change
/// cannot leave one surface behind.
ColorScheme tyLogColorScheme(Brightness brightness) =>
    brightness == Brightness.light
    ? ColorScheme.fromSeed(
        seedColor: kSeedColor,
        brightness: Brightness.light,
        surface: kLightSurface,
        onSurfaceVariant: kLightOnSurfaceVariant,
      )
    : ColorScheme.fromSeed(
        seedColor: kSeedColor,
        brightness: Brightness.dark,
      );

/// Corner-radius scale. Small = chips/inline chips, medium = list tiles, cards
/// and popovers, large = settings-style container cards.
const kRadiusSmall = 6.0;
const kRadiusMedium = 12.0;
const kRadiusLarge = 20.0;

/// Minimum interactive size (Material/WCAG target-size guidance). Controls that
/// draw smaller than this must still *hit* at least this big.
const kMinTapTarget = 48.0;

/// Corner radius shared by the rounded [ListTile]s in the links panel.
const listTileRadius = BorderRadius.all(Radius.circular(kRadiusMedium));

/// Semantic "warning" color: Material 3 has no warning role, and the previous
/// `Colors.amber` scored 1.56:1 on the light surface — below even the 3:1
/// non-text minimum. These two clear 3:1 on their own theme's surfaces
/// (light 4.05:1, dark 10.48:1) while staying recognisably amber.
Color warningColor(ColorScheme scheme) => scheme.brightness == Brightness.dark
    ? const Color(0xFFFFC107)
    : const Color(0xFFB26A00);

/// Note kinds that represent the app's own structural taxonomy (daily
/// journal, pages, projects, …) rather than a user-defined entity.
const structuralNoteKinds = {'daily', 'note', 'project', 'article', 'research'};

/// The icon representing a note of the given [kind] — person/place/org entities
/// and structural kinds. Used by inline reference chips and entity lists so
/// person, place, project, etc. reads at a glance.
///
/// This is the *only* place a note kind becomes an icon: routing every list
/// through it is what stops "note" being `Icons.notes` on one screen and
/// `Icons.description_outlined` on the next.
IconData iconForKind(String? kind) => switch (kind) {
  'person' => Icons.person_outline,
  'place' => Icons.location_on_outlined, // map pin / locator
  'org' || 'organization' || 'company' => Icons.business_outlined,
  'project' => Icons.work_outline,
  'article' => Icons.article_outlined,
  'daily' => Icons.event_note,
  _ => Icons.description_outlined, // generic note reference
};
