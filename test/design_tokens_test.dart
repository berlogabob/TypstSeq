import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards the design-token layer introduced in `lib/widgets/constants.dart`.
///
/// The UI audit found the brand seed duplicated in three files, seven ad-hoc
/// corner radii, one note kind drawn with two different icons, and a raw
/// `Colors.amber` that failed WCAG non-text contrast at 1.56:1. Fixing those
/// once is easy; keeping them fixed is what this test is for — a source scan is
/// crude, but it fails loudly in CI the moment a literal creeps back in, which
/// no amount of review discipline reliably does.
///
/// Companion to `test/contrast_test.dart`, which checks the token *values*;
/// this checks that the tokens are actually the ones being used.
void main() {
  /// Dart sources under `lib/`, with comments stripped so a rule can be
  /// *described* in prose without tripping the rule it describes.
  final sources = <String, String>{};

  setUpAll(() {
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      sources[entity.path] = _stripComments(entity.readAsStringSync());
    }
    expect(
      sources,
      isNotEmpty,
      reason: 'no lib/*.dart found — run tests from the package root',
    );
  });

  Iterable<String> offenders(
    RegExp pattern, {
    bool Function(String path)? where,
  }) => sources.entries
      .where((e) => where == null || where(e.key))
      .where((e) => pattern.hasMatch(e.value))
      .map((e) => e.key);

  test('the brand seed lives only in the token file', () {
    expect(
      offenders(
        RegExp('0xFF0B2F44'),
        where: (path) => !path.endsWith('widgets/constants.dart'),
      ),
      isEmpty,
      reason:
          'use tyLogColorScheme(brightness) instead of re-seeding a scheme; '
          'the seed belongs to lib/widgets/constants.dart alone',
    );
  });

  test('no raw Material palette colors outside the token file', () {
    expect(
      offenders(
        RegExp(r'\bColors\.(?!transparent\b|black\b|white\b)[a-z]'),
        where: (path) => !path.endsWith('widgets/constants.dart'),
      ),
      isEmpty,
      reason:
          'palette colors bypass the theme and are unchecked for contrast — '
          'use a ColorScheme role, or warningColor() for warnings. '
          '(transparent/black/white are allowed: they are absolutes used for '
          'compositing, not hue choices.)',
    );
  });

  test('corner radii come from the radius scale', () {
    // Scoped to the widget layer, the editor chrome and the shell. Painters
    // (graph, voronoi) do their own geometry and are deliberately out of scope.
    expect(
      offenders(
        RegExp(r'BorderRadius\.circular\(\s*\d'),
        where: (path) =>
            path.contains('lib/widgets/') ||
            path.contains('lib/rich_editor/') ||
            path.endsWith('lib/app_mobile.dart'),
      ),
      isEmpty,
      reason:
          'use kRadiusSmall / kRadiusMedium / kRadiusLarge — seven unrelated '
          'radii is how a UI drifts out of alignment with itself',
    );
  });

  test('a note kind becomes an icon in exactly one place', () {
    expect(
      offenders(
        RegExp(r'Icons\.notes\b'),
        where: (path) => !path.endsWith('widgets/constants.dart'),
      ),
      isEmpty,
      reason:
          'route note kinds through iconForKind() — Icons.notes here and '
          'Icons.description_outlined there is the same concept drawn twice',
    );
  });
}

/// Removes `//` and `/* */` comments so prose describing a banned literal does
/// not itself trip the ban. Deliberately simple: it does not track string
/// literals, which is fine here because the patterns above are all code shapes.
String _stripComments(String source) => source
    .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '')
    .split('\n')
    .map((line) {
      final comment = line.indexOf('//');
      return comment < 0 ? line : line.substring(0, comment);
    })
    .join('\n');
