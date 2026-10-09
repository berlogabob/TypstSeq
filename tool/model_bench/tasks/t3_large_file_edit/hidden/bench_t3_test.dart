import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/nextcloud_sync.dart';
import 'package:tylog/workspace_controller.dart';

void main() {
  test('proxy outage text', () {
    for (final code in [502, 503, 504, 520, 525, 530]) {
      expect(
        friendlySyncError(WebDavStatusException('MKCOL $code', code)),
        'Nextcloud server is unreachable ($code). Your notes are saved on this device; sync will retry.',
      );
    }
    expect(friendlySyncError(WebDavStatusException('MKCOL 409', 409)), 'Sync stopped before completion: MKCOL 409');
    expect(friendlySyncError(WebDavStatusException('PUT 500', 500)), 'Sync stopped before completion: PUT 500');
    expect(friendlySyncError(WebDavStatusException('PUT 531', 531)), 'Sync stopped before completion: PUT 531');
    expect(friendlySyncError(WebDavStatusException('GET 404', 404)), 'The configured Nextcloud folder was not found.');
    expect(friendlySyncError(TimeoutException('x')), startsWith('Nextcloud connection was interrupted'));
    expect(friendlySyncError(const FormatException('x')), 'Sync data could not be read.');
  });
}
