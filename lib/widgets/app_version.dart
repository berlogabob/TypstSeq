import 'package:flutter/services.dart' show rootBundle;

Future<String> appVersion() async =>
    RegExp(r'^version:\s*(.+)$', multiLine: true)
        .firstMatch(await rootBundle.loadString('pubspec.yaml'))
        ?.group(1)
        ?.trim() ??
    'unknown';
