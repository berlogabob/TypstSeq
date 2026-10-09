Edit ONE file, lib/widgets/editor_panel.dart. Do not modify or create any other file.

lib/widgets/constants.dart defines design tokens (read it): spacing `kSpace4`, `kSpace8`, `kSpace12`, `kSpace16`, `kSpace24`, `kEditorInset` (18), tap target `kMinTapTarget` (48), radii `kRadiusSmall/Medium/Large`, and durations `kMotionDock` (150 ms), `kMotionStatus` (200 ms), `kMotionGraphZoom` (260 ms).

In editor_panel.dart replace hard-coded spacing, padding, size, radius and duration literals with the token that has EXACTLY the same value, and add `import 'constants.dart';`.

Hard rules:
- Never change a value. A literal with no exactly-equal token stays as it is.
- Do not change behaviour, text, widget structure, comments or anything else.
- `const Duration(milliseconds: 150)` becomes `kMotionDock` (the token is already a Duration).
- `flutter analyze --no-pub lib/widgets/editor_panel.dart` must report no issues.
