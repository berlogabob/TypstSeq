import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/nextcloud_sync.dart';
import 'package:tylog/workspace_controller.dart';

void main() {
  test('sync stage ids read as plain text', () {
    expect(syncStageLabel('push-local'), 'Uploading changes');
    expect(
      syncStageLabel('sync-file 3/9 · notes/a.typ'),
      'Syncing 3/9 · notes/a.typ',
    );
    expect(syncStageLabel('Uploading…'), 'Uploading…');
  });

  test('every stage the engine reports has a label', () {
    final ids = RegExp(r"progress\('([a-z-]+)[ ']");
    for (final file in [
      'lib/nextcloud_sync.dart',
      'lib/nextcloud_sync/path_sync.dart',
    ]) {
      for (final m in ids.allMatches(File(file).readAsStringSync())) {
        if (m[1] == 'sync-file') continue; // carries a counter, tested above
        expect(syncStageLabel(m[1]!), isNot(m[1]), reason: m[1]);
      }
    }
  });

  test('proxy outages read as an unreachable server', () {
    for (final code in [502, 503, 504, 520, 530]) {
      expect(
        friendlySyncError(WebDavStatusException('MKCOL $code', code)),
        'Nextcloud server is unreachable ($code). '
        'Your notes are saved on this device; sync will retry.',
      );
    }
    expect(
      friendlySyncError(WebDavStatusException('MKCOL 409', 409)),
      'Sync stopped before completion: MKCOL 409',
    );
  });
}
