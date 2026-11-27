import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
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
      // Forward slashes, so the path checks below also hold on Windows.
      sources[entity.path.replaceAll(r'\', '/')] = _stripComments(
        entity.readAsStringSync(),
      );
    }
    expect(
      sources,
      isNotEmpty,
      reason: 'no lib/*.dart found — run tests from the package root',
    );
  });

  bool isFile(String path, String name) => path.endsWith(name);

  Iterable<String> offenders(
    RegExp pattern, {
    bool Function(String path)? where,
  }) => sources.entries
      .where((e) => where == null || where(e.key))
      .where((e) => pattern.hasMatch(e.value))
      .map((e) => e.key);

  test('padding, gaps and Wrap spacing use equal-value tokens', () {
    // Every file under lib/, so a new screen cannot drift the way the boards
    // and review sheets did while this only checked a list of migrated files.
    for (final MapEntry(key: path, value: source) in sources.entries) {
      if (isFile(path, 'lib/widgets/constants.dart')) continue;
      for (final padding in RegExp(
        r'EdgeInsets(?:Directional)?\.(?:all|only|symmetric|fromLTRB)\([^)]*\)',
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
          r'\b(?:spacing|runSpacing):\s*(?:4|8|12|16|24)(?:\.0)?\s*[,)\n]',
        ).hasMatch(source),
        isFalse,
        reason: '$path: use kSpace* for spacing / runSpacing',
      );
      expect(
        RegExp(
          r'SizedBox\((?:width|height):\s*(?:4|8|12|16|18|24)(?:\.0)?\)',
        ).hasMatch(source),
        isFalse,
        reason: '$path: use kSpace* for SizedBox gaps',
      );
    }
    expect(
      [kSpace4, kSpace8, kSpace12, kSpace16, kSpace24, kEditorInset],
      [4, 8, 12, 16, 24, 18],
    );
  });

  test('animation durations use motion tokens', () {
    expect(
      offenders(
        RegExp(
          r'duration:\s*const Duration\(milliseconds:\s*(?:150|200|260)\)',
        ),
        where: (path) => !isFile(path, 'lib/widgets/constants.dart'),
      ),
      isEmpty,
      reason: 'use kMotionDock / kMotionStatus / kMotionGraphZoom',
    );
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

  testWidgets('app component themes are set in light and dark modes', (
    tester,
  ) async {
    for (final brightness in Brightness.values) {
      late ThemeData theme;
      await tester.pumpWidget(
        MaterialApp(
          theme: tyLogTheme(Brightness.light),
          darkTheme: tyLogTheme(Brightness.dark),
          themeMode: brightness == Brightness.light
              ? ThemeMode.light
              : ThemeMode.dark,
          home: Builder(
            builder: (context) {
              theme = Theme.of(context);
              return const Scaffold(body: SizedBox.shrink());
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(theme.brightness, brightness);
      expect(theme.chipTheme.shape, isNotNull);
      expect(theme.dialogTheme.shape, isNotNull);
      expect(theme.cardTheme.shape, isNotNull);
      expect(theme.bottomSheetTheme.shape, isNotNull);
      expect(theme.filledButtonTheme.style?.shape?.resolve({}), isNotNull);
      expect(theme.outlinedButtonTheme.style?.shape?.resolve({}), isNotNull);
      expect(theme.textButtonTheme.style?.shape?.resolve({}), isNotNull);
      expect(theme.appBarTheme.surfaceTintColor, Colors.transparent);
      expect(theme.snackBarTheme.behavior, SnackBarBehavior.floating);
      // Regression: a global outline border boxed the borderless editor field.
      expect(theme.inputDecorationTheme.border, InputBorder.none);
      expect(
        theme.listTileTheme.contentPadding,
        const EdgeInsets.symmetric(horizontal: kSpace16),
      );
      expect(theme.dividerTheme.space, kSpace16);
      expect(
        theme.hintColor,
        brightness == Brightness.light
            ? kLightHint
            : theme.colorScheme.onSurfaceVariant,
      );
    }
  });

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
    // Painters (graph, voronoi) compute canvas geometry such as
    // `Radius.circular(4 / scale)`, which this pattern does not match.
    expect(
      offenders(
        RegExp(r'BorderRadius\.circular\(\s*\d|Radius\.circular\(\s*\d+\s*\)'),
        where: (path) => !isFile(path, 'lib/widgets/constants.dart'),
      ),
      isEmpty,
      reason:
          'use kRadiusSmall / kRadiusMedium / kRadiusLarge — seven unrelated '
          'radii is how a UI drifts out of alignment with itself',
    );
  });

  test('bottom sheets open through showAppSheet', () {
    expect(
      offenders(
        RegExp(r'\bshowModalBottomSheet\b'),
        where: (path) => !isFile(path, 'lib/widgets/ds/app_sheet.dart'),
      ),
      isEmpty,
      reason:
          'call showAppSheet(context, builder: ...) and return an AppSheet so '
          'every sheet has the same handle, title and gutters',
    );
  });

  test('icon sizes come from the icon scale', () {
    expect(
      offenders(
        RegExp(r'\bsize:\s*(?:16|18|20|24|48)(?:\.0)?(?![\w.])'),
        where: (path) => !isFile(path, 'lib/widgets/constants.dart'),
      ),
      isEmpty,
      reason:
          'use kIconInline (16) / kIconDense (18) / kIconSmall (20) / kIcon '
          '(24) / kIconLarge (48)',
    );
  });

  test('text sizes come from the text theme', () {
    // 0.01 is the editor's zero-width marker style, not a type size.
    expect(
      offenders(RegExp(r'\bfontSize:\s*[1-9]')),
      isEmpty,
      reason: 'use a textTheme role (bodyMedium, titleLarge, ...)',
    );
  });

  test('every design-system component is exported and documented', () {
    final barrel = sources['lib/widgets/ds/ds.dart']!;
    final reference = File('docs/design-system.md').readAsStringSync();
    for (final path in sources.keys.where(
      (p) => p.startsWith('lib/widgets/ds/') && !isFile(p, 'ds.dart'),
    )) {
      final file = path.split('/').last;
      expect(barrel, contains("export '$file';"), reason: path);
      // Public classes only; a private State is part of its widget.
      for (final match in RegExp(
        r'^class ([A-Z]\w*) extends',
        multiLine: true,
      ).allMatches(sources[path]!)) {
        expect(
          reference,
          contains('`${match.group(1)}`'),
          reason: '${match.group(1)} is missing from docs/design-system.md',
        );
        expect(
          File(path).readAsStringSync(),
          matches(
            RegExp('///[^\\n]*\\n(?:///[^\\n]*\\n)*class ${match.group(1)} '),
          ),
          reason: '${match.group(1)} needs a doc comment',
        );
      }
    }
  });

  test('dialogs: Cancel first, a filled primary, no OK/Yes/No', () {
    final problems = <String>[];
    // showConfirmDialog builds its filled primary in two branches.
    for (final path in sources.keys.where(
      (p) => !isFile(p, 'lib/widgets/dialogs.dart'),
    )) {
      // Raw text: comment stripping would cut string literals such as URLs.
      final source = File(path).readAsStringSync();
      for (final match in RegExp(r'AlertDialog\(').allMatches(source)) {
        final dialog = _withoutNestedDialogs(_balanced(source, match.end - 1));
        final at = dialog.indexOf('actions:');
        if (at < 0) continue;
        final actions = dialog.substring(at);
        final where = '$path:${_line(source, match.start)}';
        if (RegExp(
          r'''Text\(\s*['"](?:OK|Ok|Yes|No)['"]''',
        ).hasMatch(actions)) {
          problems.add('$where: name the action instead of OK/Yes/No');
        }
        final buttons = RegExp(
          r'\b(?:Text|Filled|Outlined|Elevated)Button(?:\.(?!styleFrom)\w+)?\(',
        ).allMatches(actions).toList();
        // Three buttons do not fit a phone-width dialog and stack. The one
        // exception is the article merge, a genuine three-way decision shown
        // in a full-width dialog.
        if (buttons.length > 2 && !dialog.contains('Article changed')) {
          problems.add(
            '$where: at most two actions; move a secondary one into the body',
          );
        }
        final cancel = actions.indexOf("Text('Cancel')");
        if (cancel < 0) continue;
        if (buttons.length < 2) continue;
        if (buttons.first.start > cancel ||
            buttons.length > 1 && buttons[1].start < cancel) {
          problems.add('$where: Cancel must be the first action');
        }
        if (!RegExp(r'\bFilledButton(?:\.\w+)?\(').hasMatch(actions)) {
          problems.add('$where: the primary action must be a FilledButton');
        }
      }
    }
    expect(
      problems,
      isEmpty,
      reason:
          'for yes/no questions use showConfirmDialog; dialogs that collect '
          'input follow the same order (docs/design-system.md)',
    );
  });

  test('whole-surface messages use AppEmptyState', () {
    expect(
      offenders(RegExp(r'Center\(\s*child:\s*(?:const\s+)?Text\(')),
      isEmpty,
      reason:
          'a message that fills a tab or pane is AppEmptyState (or '
          'AppEmptyState.error); an empty section in a list is a one-line row',
    );
  });

  test('spinners are LoadingIndicator', () {
    expect(
      offenders(
        RegExp(r'\bCircularProgressIndicator\('),
        where: (path) => !isFile(path, 'lib/widgets/loading.dart'),
      ),
      isEmpty,
      reason: 'use LoadingIndicator(size:, strokeWidth:) so spinners match',
    );
  });

  test('plain snackbars go through showSnack', () {
    expect(
      offenders(
        RegExp(r'\.showSnackBar\('),
        where: (path) => !isFile(path, 'lib/widgets/snack.dart'),
      ),
      isEmpty,
      reason:
          'call showSnack(context, message, action:, duration:) so message '
          'presentation changes in one place',
    );
  });

  test('glyphs owned by AppIcons are not used directly', () {
    expect(
      offenders(
        RegExp(
          r'(?<!\w)Icons\.(?:settings|settings_outlined|more_horiz|more_vert|'
          r'close|warning|warning_amber|warning_amber_outlined|'
          r'warning_amber_rounded|edit|edit_outlined|delete|delete_outline|'
          r'delete_outlined|sync|sync_outlined|folder_open|link)\b',
        ),
        where: (path) => !isFile(path, 'lib/widgets/app_icons.dart'),
      ),
      isEmpty,
      reason:
          'one icon per meaning: use AppIcons.settings / overflow / close / '
          'warning / edit / delete / sync / folderOpen / link',
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

/// The text of the call whose `(` is at [open], up to its matching `)`.
/// Skips string literals and `//` comments so parentheses inside them do not
/// count.
String _balanced(String source, int open) {
  var depth = 0;
  String? quote;
  for (var i = open; i < source.length; i++) {
    final c = source[i];
    if (quote != null) {
      if (c == r'\') {
        i++;
      } else if (c == quote) {
        quote = null;
      }
    } else if (c == '/' && i + 1 < source.length && source[i + 1] == '/') {
      final end = source.indexOf('\n', i);
      if (end < 0) break;
      i = end;
    } else if (c == "'" || c == '"') {
      quote = c;
    } else if (c == '(') {
      depth++;
    } else if (c == ')' && --depth == 0) {
      return source.substring(open, i + 1);
    }
  }
  return source.substring(open);
}

int _line(String source, int offset) =>
    '\n'.allMatches(source.substring(0, offset)).length + 1;

/// [dialog] with any dialog opened from inside it cut out, so a nested
/// dialog's actions are not read as the outer dialog's.
String _withoutNestedDialogs(String dialog) {
  var text = dialog;
  for (
    var at = text.indexOf('AlertDialog(', 1);
    at >= 0;
    at = text.indexOf('AlertDialog(', at + 1)
  ) {
    final nested = _balanced(text, at + 'AlertDialog'.length);
    text = text.replaceRange(at, at + 'AlertDialog'.length + nested.length, '');
  }
  return text;
}
