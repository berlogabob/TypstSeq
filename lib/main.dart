import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'app_mobile.dart';
import 'diagnostics/jank_monitor.dart';
import 'diagnostics/startup_trace.dart';
// Not used by the UI: pulls vaultServiceMain into the compiled program so the
// background engine's entrypoint lookup can find it. @pragma alone cannot save
// a function in a file the import graph never reaches.
// ignore: unused_import
import 'vault_service.dart';
import 'rich_editor.dart' show debugEnableEditorWindow;
import 'widgets/fold_store.dart';
export 'app_mobile.dart';

void main() {
  startupClock.start();
  WidgetsFlutterBinding.ensureInitialized();
  startJankMonitor();
  // P12k bounded editing window: off by default until the on-device keyboard
  // check passes; `--dart-define=TYLOG_EDITOR_WINDOW=true` turns it on.
  debugEnableEditorWindow = const bool.fromEnvironment('TYLOG_EDITOR_WINDOW');
  // ponytail: loaded off the startup path; a picture built before it lands
  // shows unfolded until its note is opened again.
  unawaited(
    getApplicationSupportDirectory()
        .then((dir) => FoldStore.open(File('${dir.path}/fold_state.json')))
        .then((store) => FoldStore.instance = store, onError: (_) => null),
  );
  runApp(const TyLogApp());
}
