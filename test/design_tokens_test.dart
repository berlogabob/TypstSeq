import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:tylog/widgets/constants.dart';
import 'package:tylog/widgets/task_clock.dart';
import 'package:tylog/models.dart';

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

  test('migrated padding, gaps and Wrap spacing use equal-value tokens', () {
    const migrated = {
      'lib/app_mobile.dart',
      'lib/knowledge_screen.dart',
      'lib/widgets/work_surface.dart',
      'lib/widgets/entity_header.dart',
      'lib/widgets/idea_hub.dart',
      'lib/widgets/screenshot_strip.dart',
      'lib/widgets/linked_references.dart',
      'lib/widgets/settings_sheet.dart',
      'lib/widgets/vaults_sheet.dart',
      'lib/widgets/note_picker_sheet.dart',
      'lib/widgets/nextcloud_connect_dialog.dart',
      'lib/widgets/task_clock.dart',
      'lib/widgets/task_chip_strip.dart',
      'lib/widgets/property_select_chip.dart',
      'lib/widgets/editor_panel.dart',
      'lib/app_mobile/markdown_import_flow.dart',
      'lib/rich_editor/editor_widgets.dart',
      'lib/month_calendar.dart',
    };
    for (final path in migrated) {
      final source = sources[path]!;
      for (final padding in RegExp(
        r'EdgeInsets\.(?:all|only|symmetric|fromLTRB)\([^)]*\)',
      ).allMatches(source)) {
        expect(
          RegExp(
            r'(?<![\w.])(?:4|8|12|16|18|24)(?:\.0)?(?![\w.])',
          ).hasMatch(padding.group(0)!),
          isFalse,
          reason: '$path: ${padding.group(0)}',
        );
      }
      expect(
        RegExp(
          r'\b(?:spacing|runSpacing):\s*(?:4|8|12|16|24)(?:\.0)?\s*[,\n]',
        ).hasMatch(source),
        isFalse,
        reason: path,
      );
      expect(
        RegExp(
          r'SizedBox\((?:width|height):\s*(?:4|8|12|16|18|24)\)',
        ).hasMatch(source),
        isFalse,
        reason: path,
      );
    }
    expect(
      [kSpace4, kSpace8, kSpace12, kSpace16, kSpace24, kEditorInset],
      [4, 8, 12, 16, 24, 18],
    );
  });

  test('migrated animation durations use motion tokens', () {
    for (final path in [
      'lib/widgets/editor_panel.dart',
      'lib/rich_editor/editor_widgets.dart',
      'lib/app_mobile.dart',
      'lib/graph.dart',
      'lib/voronoi_view.dart',
    ]) {
      expect(
        RegExp(
          r'duration:\s*const Duration\(milliseconds:\s*(?:150|200|260)\)',
        ).hasMatch(sources[path]!),
        isFalse,
        reason: path,
      );
    }
    expect(
      [
        kMotionDock.inMilliseconds,
        kMotionStatus.inMilliseconds,
        kMotionGraphZoom.inMilliseconds,
      ],
      [150, 200, 260],
    );
  });

  testWidgets(
    'task clock title has a 48dp hit area with keyboard and larger text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var opened = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(320, 600),
              viewInsets: EdgeInsets.only(bottom: 200),
              textScaler: TextScaler.linear(2),
            ),
            child: Scaffold(
              body: TaskClock(
                task: const TaskRef(
                  id: 't',
                  notePath: 'notes/a.typ',
                  text: 'Task title',
                ),
                onOpen: () => opened++,
                onStop: (_) async {},
              ),
            ),
          ),
        ),
      );
      final target = find
          .ancestor(of: find.text('Task title'), matching: find.byType(InkWell))
          .first;
      final bounds = tester.getRect(target);
      expect(bounds.height, greaterThanOrEqualTo(kMinTapTarget));
      expect(bounds.width, greaterThanOrEqualTo(kMinTapTarget));
      await tester.tapAt(Offset(bounds.center.dx, bounds.top + 1));
      expect(opened, 1);
      expect(tester.takeException(), isNull);
    },
  );

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
