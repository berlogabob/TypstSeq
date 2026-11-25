cat > lib/sync_stage_text.dart <<'DART'
String syncStageText(String stage) {
  final cut = stage.indexOf(' · ');
  final id = cut < 0 ? stage : stage.substring(0, cut);
  final detail = cut < 0 ? '' : stage.substring(cut);
  if (id.startsWith('sync-file ')) return 'Syncing ${id.substring(10)}$detail';
  final label = const {
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
  }[id];
  return label == null ? stage : '$label$detail';
}
DART
