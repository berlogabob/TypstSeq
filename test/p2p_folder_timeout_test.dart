import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('folder transfer permits a full vault transfer', () {
    final source = File(
      'packages/typst_flutter/rust/src/api/p2p_folder.rs',
    ).readAsStringSync();
    expect(source, contains('const TRANSFER_TIMEOUT_SECS: u64 = 7200;'));
    expect(
      RegExp(
        r'Duration::from_secs\(TRANSFER_TIMEOUT_SECS\)',
      ).allMatches(source).length,
      2,
    );
  });
}
