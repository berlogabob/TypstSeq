import 'dart:io';
import 'package:test/test.dart';

void main() {
  group('No Flutter imports', () {
    test('All .dart files in lib/ should not import Flutter or dart:ui', () {
      final libDir = Directory('lib');
      final errors = <String>[];

      void checkDirectory(Directory dir) {
        for (final file in dir.listSync(recursive: true)) {
          if (file is File && file.path.endsWith('.dart')) {
            final content = file.readAsStringSync();
            if (content.contains('package:flutter') ||
                content.contains('dart:ui')) {
              errors.add(file.path);
            }
          }
        }
      }

      checkDirectory(libDir);
      if (errors.isNotEmpty) {
        fail(
          'The following files contain Flutter or dart:ui imports:\n${errors.join('\n')}',
        );
      }
    });
  });
}
