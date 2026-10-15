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
    expect(friendlyVaultPath('/Users/a/vault'), '/Users/a/vault');
  });
}
