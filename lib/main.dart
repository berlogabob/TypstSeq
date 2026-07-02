import 'package:flutter/material.dart';

import 'app_mobile.dart' if (dart.library.html) 'app_web.dart';
export 'app_mobile.dart' if (dart.library.html) 'app_web.dart';

void main() => runApp(const TyLogApp());
