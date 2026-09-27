import 'package:flutter/material.dart';

import 'app_mobile.dart';
// Not used by the UI: pulls vaultServiceMain into the compiled program so the
// background engine's entrypoint lookup can find it. @pragma alone cannot save
// a function in a file the import graph never reaches.
// ignore: unused_import
import 'vault_service.dart';
import 'rich_editor.dart' show debugEnableEditorWindow;
export 'app_mobile.dart';

void main() {
  // P12k bounded editing window: off by default until the on-device keyboard
  // check passes; `--dart-define=TYLOG_EDITOR_WINDOW=true` turns it on.
  debugEnableEditorWindow = const bool.fromEnvironment('TYLOG_EDITOR_WINDOW');
  runApp(const TyLogApp());
}
