import 'package:flutter/material.dart';

import 'app_mobile.dart';
// Not used by the UI: pulls vaultServiceMain into the compiled program so the
// background engine's entrypoint lookup can find it. @pragma alone cannot save
// a function in a file the import graph never reaches.
// ignore: unused_import
import 'vault_service.dart';
export 'app_mobile.dart';

void main() => runApp(const TyLogApp());
