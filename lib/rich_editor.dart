import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
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
