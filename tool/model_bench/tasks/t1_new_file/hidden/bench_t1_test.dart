import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/sync_stage_text.dart';

void main() {
  test('stage text', () {
    const table = {
      'load-local-state': 'Checking local notes',
      'scan-local-shortcut': 'Checking local notes',
      'scan-local': 'Checking local notes',
      'probe-root': 'Checking server',
      'prepare-remote-folder': 'Connecting to server',
      'list-remote': 'Reading server list',
      'push-local': 'Uploading changes',
      'detect-renames': 'Matching renamed notes',
      'download-archive': 'Downloading vault',
      'validate-archive': 'Checking download',
      'extract-archive': 'Unpacking download',
      'verify-remote-writes': 'Verifying uploads',
      'save-local-state': 'Finishing sync',
    };
    table.forEach((id, text) {
      expect(syncStageText(id), text);
      expect(syncStageText('$id · notes/a.typ'), '$text · notes/a.typ');
    });
    expect(syncStageText('sync-file 3/9'), 'Syncing 3/9');
    expect(syncStageText('sync-file 12/400 · daily/x.typ'), 'Syncing 12/400 · daily/x.typ');
    expect(syncStageText('detect-renames · a.typ → b.typ'), 'Matching renamed notes · a.typ → b.typ');
    expect(syncStageText('Uploading…'), 'Uploading…');
    expect(syncStageText('idle'), 'idle');
    expect(syncStageText(''), '');
  });
}
