import 'package:test/test.dart';
import 'package:tylog_core/sync_paths.dart';

void main() {
  test('local JSON files are excluded from every sync root', () {
    for (final root in ['_system/settings', 'notes', 'assets', 'outputs']) {
      expect(isSyncableVaultPath('$root/x.local.json'), isFalse);
      expect(isSyncableVaultPath('$root/x.json'), isTrue);
    }
  });
}
