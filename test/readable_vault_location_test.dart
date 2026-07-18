import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/vault_registry.dart';

void main() {
  test('formats vault locations for display', () {
    expect(
      readableVaultLocation(
        'content://com.android.providers.downloads.documents/tree/'
        'raw%3A%2Fstorage%2Femulated%2F0%2FDownload%2FTyLog',
      ),
      'Download/TyLog',
    );
    expect(
      readableVaultLocation(
        'content://com.android.externalstorage.documents/tree/'
        'primary%3ADocuments%2FTyLog',
      ),
      'Documents/TyLog',
    );
    expect(
      readableVaultLocation('/Users/x/Nextcloud/TyLogVault'),
      '/Users/x/Nextcloud/TyLogVault',
    );
    expect(
      readableVaultLocation('content://provider/not-a-tree/My%20Vault'),
      'My Vault',
    );
  });
}
