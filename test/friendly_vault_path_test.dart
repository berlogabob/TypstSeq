import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/widgets/vaults_sheet.dart';

void main() {
  test('friendlyVaultPath', () {
    expect(
      friendlyVaultPath(
        'content://com.android.externalstorage.documents/tree/primary%3ADownload%2FTyLog',
      ),
      'Internal storage/Download/TyLog',
    );
    expect(
      friendlyVaultPath(
        'content://com.android.providers.downloads.documents/tree/raw%3A%2Fstorage%2Femulated%2F0%2FDownload%2FTyLogModTest',
      ),
      'Internal storage/Download/TyLogModTest',
    );
    expect(friendlyVaultPath('/Users/a/vault'), '/Users/a/vault');
  });
}
