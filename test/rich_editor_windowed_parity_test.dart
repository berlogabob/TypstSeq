import 'package:tylog/rich_editor.dart';

import 'rich_editor_test.dart' as base;

/// P12k parity: the whole rich-editor suite against the bounded window.
void main() {
  debugEnableEditorWindow = true;
  base.main();
}
