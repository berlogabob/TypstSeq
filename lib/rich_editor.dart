import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderEditable, RenderParagraph;
import 'package:flutter/services.dart';
import 'package:tylog_core/scanner.dart';
import 'package:tylog_core/values.dart';

import 'controlled_editor.dart';
import 'widgets/constants.dart';
import 'editor_autocomplete.dart';
import 'widgets/loading.dart';
import 'widgets/task_checkbox.dart';

export 'editor_autocomplete.dart'
    show
        MentionSuggestion,
        MentionKind,
        AutocompleteTriggerKind,
        mentionScore,
        mentionSubtitle;

part 'rich_editor/document_model.dart';
part 'rich_editor/editing_controller.dart';
part 'rich_editor/editor_widgets.dart';
part 'rich_editor/window_controller.dart';

bool shouldUseVirtualPlainEditor(TyLogEditingController controller) {
  final document = controller.document;
  return (controller.text.length >= 32 * 1024 ||
          document.blocks.length >= 200) &&
      document.blocks.every(
        (block) =>
            block.style == TyLogBlockStyle.paragraph &&
            block.parts.length == 1 &&
            !block.parts.single.isAtom,
      );
}

/// Keeps the popup clear of the caret line, including the on-screen keyboard.
Rect autocompletePopupRect(Rect caret, Size viewport, Size desired) {
  const gap = 4.0;
  final below = math.max(0.0, viewport.height - caret.bottom - gap);
  final above = math.max(0.0, caret.top - gap);
  final useBelow = below >= desired.height || below >= above;
  final height = math.min(desired.height, useBelow ? below : above);
  final width = math.min(desired.width, viewport.width);
  return Rect.fromLTWH(
    caret.left.clamp(0.0, math.max(0.0, viewport.width - width)),
    useBelow ? caret.bottom + gap : caret.top - gap - height,
    width,
    height,
  );
}
