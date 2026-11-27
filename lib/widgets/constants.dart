import 'package:material_ui/material_ui.dart';
import 'package:tylog_core/tylog_core.dart' show Ontology, kCoreOntology;
import 'app_icons.dart';
import '../kind_registry.dart';

/// Note kinds that represent the app's own structural taxonomy (daily
/// journal, pages, projects, …) rather than a user-defined entity. Defined in
/// tylog_core next to the validation vocabulary so the two can't drift.
export 'package:tylog_core/models.dart'
    show structuralNoteKinds, entityNoteKinds, standardNoteKinds;

// ---------------------------------------------------------------------------
// Design tokens
//
// Single source of truth for values the UI used to decide per-widget. Before
// this file the brand seed appeared in three places, seven different corner
// radii were in use, and "warning" was a raw `Colors.amber` that failed WCAG
// non-text contrast at 1.56:1. Anything visual and repeated belongs here so a
// change lands everywhere at once — `test/design_tokens_test.dart` and
// `test/contrast_test.dart` keep it that way.
//
// Naming: every token starts with `k`. Scales that are picked by value are
// named by value (`kSpace16`); scales picked by role are named by role
// (`kRadiusSmall`, `kIconDense`, `kMotionDock`). Brightness-dependent values
// are functions of the scheme (`warningColor`). Components built from these
// tokens live in `ds/` and are documented in `docs/design-system.md`.
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
    : ColorScheme.fromSeed(seedColor: kSeedColor, brightness: Brightness.dark);

/// App component defaults; unspecified properties retain Material 3 defaults.
ThemeData tyLogTheme(Brightness brightness) {
  final scheme = tyLogColorScheme(brightness);
  const smallShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.all(Radius.circular(kRadiusSmall)),
  );
  const mediumShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.all(Radius.circular(kRadiusMedium)),
  );
  const largeShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.all(Radius.circular(kRadiusLarge)),
  );
  const buttonStyle = ButtonStyle(shape: WidgetStatePropertyAll(mediumShape));
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    hintColor: brightness == Brightness.light
        ? kLightHint
        : scheme.onSurfaceVariant,
    cardTheme: const CardThemeData(shape: mediumShape),
    dialogTheme: const DialogThemeData(shape: largeShape),
    chipTheme: const ChipThemeData(shape: smallShape),
    filledButtonTheme: const FilledButtonThemeData(style: buttonStyle),
    outlinedButtonTheme: const OutlinedButtonThemeData(style: buttonStyle),
    textButtonTheme: const TextButtonThemeData(style: buttonStyle),
    appBarTheme: const AppBarThemeData(surfaceTintColor: Colors.transparent),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    bottomSheetTheme: const BottomSheetThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(kRadiusLarge)),
      ),
    ),
    // The app was borderless before D6; fields that want a border set their own.
    inputDecorationTheme: const InputDecorationThemeData(
      border: InputBorder.none,
    ),
    listTileTheme: const ListTileThemeData(
      contentPadding: EdgeInsets.symmetric(horizontal: kSpace16),
    ),
    dividerTheme: DividerThemeData(
      color: scheme.outlineVariant,
      space: kSpace16,
      thickness: 1,
    ),
  );
}

/// Colours for content drawn over an image. Scrims are black and the ink on
/// them is white regardless of app brightness, because the image underneath
/// does not follow the theme.
const kImageGradientScrim = Color(0x99000000);
const kImageControlScrim = Color(0x66000000);
const kOnImage = Color(0xFFFFFFFF);

/// Brief highlight on the text a search result opened at (amber, 55%).
const kSearchRevealFill = Color(0x8CFFC107);

/// Corner-radius scale. Small = chips/inline chips, medium = list tiles, cards
/// and popovers, large = settings-style container cards.
const kRadiusSmall = 6.0;
const kRadiusMedium = 12.0;
const kRadiusLarge = 20.0;

/// Corner radius shared by rounded [ListTile]s (links panel, [AppTile]).
const kRadiusListTile = BorderRadius.all(Radius.circular(kRadiusMedium));

/// Icon sizes. Inline = glyphs inside chips and badges, dense = leading icons
/// of dense rows, small = compact controls, default = standard tile icons,
/// large = the focal icon of an empty or error state.
const kIconInline = 16.0;
const kIconDense = 18.0;
const kIconSmall = 20.0;
const kIcon = 24.0;
const kIconLarge = 48.0;

/// Minimum interactive size (Material/WCAG target-size guidance). Controls that
/// draw smaller than this must still *hit* at least this big.
const kMinTapTarget = 48.0;

/// Space tokens: 4, 8, 12, 16, 24. [kEditorInset] is the one named exception:
/// the side inset of writing surfaces.
const kSpace4 = 4.0;
const kSpace8 = 8.0;
const kSpace12 = 12.0;
const kSpace16 = 16.0;
const kSpace24 = 24.0;
const kEditorInset = 18.0;

/// Height of a collapsed image's visible strip.
const kImageFoldHeight = 64.0;

/// Motion tokens: 150ms, 200ms, 260ms
const kMotionDock = Duration(milliseconds: 150);
const kMotionStatus = Duration(milliseconds: 200);
const kMotionGraphZoom = Duration(milliseconds: 260);

/// Semantic "warning" color: Material 3 has no warning role, and the previous
/// `Colors.amber` scored 1.56:1 on the light surface — below even the 3:1
/// non-text minimum. These two clear 3:1 on their own theme's surfaces
/// (light 4.05:1, dark 10.48:1) while staying recognisably amber.
Color warningColor(ColorScheme scheme) => scheme.brightness == Brightness.dark
    ? const Color(0xFFFFC107)
    : const Color(0xFFB26A00);

/// Stable names persisted in the vault's kind registry.
const kindIconPalette = <String, IconData>{
  'person': Icons.person_outline,
  'place': Icons.location_on_outlined,
  'business': Icons.business_outlined,
  'work': Icons.work_outline,
  'science': Icons.science_outlined,
  'school': Icons.school_outlined,
  'groups': Icons.groups_outlined,
  'account_tree': Icons.account_tree_outlined,
  'hub': Icons.hub_outlined,
  'inventory': Icons.inventory_outlined,
  'warehouse': Icons.warehouse_outlined,
  'build': Icons.build_outlined,
  'event': Icons.event_outlined,
  'language': Icons.language_outlined,
  'folder': Icons.folder_outlined,
  'flag': Icons.flag_outlined,
  'star': Icons.star_outline,
  'bookmark': Icons.bookmark_outline,
  'lightbulb': Icons.lightbulb_outline,
  'memory': Icons.memory_outlined,
  'palette': Icons.palette_outlined,
  'music_note': Icons.music_note_outlined,
  'sports_esports': Icons.sports_esports_outlined,
  'menu_book': Icons.menu_book_outlined,
  'apartment': Icons.apartment_outlined,
  'computer': Icons.computer_outlined,
  'camera': Icons.camera_outlined,
  'local_library': Icons.local_library_outlined,
  'biotech': Icons.biotech_outlined,
  'category': Icons.category_outlined,
};

/// The active vault's registry. HomeScreen listens for changes to repaint icons.
final kindRegistry = ValueNotifier<KindRegistry>(const {});

/// The icon representing a note of the given [kind] — person/place/org entities
/// and structural kinds. Used by inline reference chips and entity lists so
/// person, place, project, etc. reads at a glance.
///
/// This is the *only* place a note kind becomes an icon: routing every list
/// through it is what stops "note" being `Icons.notes` on one screen and
/// `Icons.description_outlined` on the next.
KindRegistry? _kindOntologyFor;
Ontology _kindOntology = Ontology.core;

/// The core ontology refined by the kind registry; rebuilt when it changes.
Ontology get kindOntology {
  if (!identical(_kindOntologyFor, kindRegistry.value)) {
    _kindOntologyFor = kindRegistry.value;
    _kindOntology = Ontology([
      kCoreOntology,
      {'classes': kindRegistry.value},
    ]);
  }
  return _kindOntology;
}

IconData iconForKind(String? kind, {KindRegistry? registry}) {
  final entry = (registry ?? kindRegistry.value)[kind];
  final icon = entry is Map ? kindIconPalette[entry['icon']] : null;
  return icon ??
      switch (kind) {
        'fixit' => Icons.bug_report_outlined,
        'task' => Icons.task_alt,
        'file' => Icons.attach_file,
        'person' => Icons.person_outline,
        'place' => Icons.location_on_outlined, // map pin / locator
        'org' || 'organization' || 'company' => Icons.business_outlined,
        'project' => Icons.work_outline,
        'idea' => Icons.lightbulb_outline,
        'article' => Icons.article_outlined,
        'screenshot' => AppIcons.screenshot,
        'daily' => AppIcons.daily,
        _ => Icons.description_outlined, // generic note reference
      };
}

/// Human labels for search result kinds, including user-defined entities.
String labelForKind(String kind, {KindRegistry? registry}) {
  final entry = (registry ?? kindRegistry.value)[kind];
  final label = entry is Map ? entry['label'] : null;
  if (label is String && label.trim().isNotEmpty) return label;
  return switch (kind) {
    'note' => 'Note',
    'daily' => 'Journal',
    'article' => 'Article',
    'audio' => 'Audio',
    'task' => 'Task',
    'file' => 'File',
    'project' => 'Project',
    'research' => 'Research',
    'idea' => 'Idea',
    'screenshot' => 'Screenshot',
    'person' => 'Person',
    'org' || 'organization' || 'company' => 'Organization',
    'place' => 'Place',
    'website' => 'Website',
    'event' => 'Event',
    _ => 'Entity',
  };
}
