import 'package:flutter_test/flutter_test.dart';
import 'package:tylog/nextcloud_sync.dart';

void main() {
  test('Nextcloud config accepts local debug secret schema', () {
    final config = NextcloudConfig.fromJson({
      'url': 'https://cloud.example/',
      'username': 'alice',
      'password': 'secret',
    });

    expect(config.serverUrl, 'https://cloud.example/');
    expect(config.rootUri.toString(), contains('/remote.php/dav/files/alice/'));
  });

  test('Nextcloud root URL uses embedded WebDAV endpoint', () {
    const config = NextcloudConfig(
      serverUrl: 'https://cloud.example/',
      username: 'alice',
      password: 'secret',
    );

    expect(
      config.rootUri.toString(),
      'https://cloud.example/remote.php/dav/files/alice/TyLogVault/',
    );
  });

  test('Nextcloud direct WebDAV URL is accepted', () {
    const config = NextcloudConfig(
      serverUrl: 'https://cloud.example/remote.php/dav/files/alice/TyLogVault',
      username: 'alice',
      password: 'secret',
    );

    expect(
      config.rootUri.toString(),
      'https://cloud.example/remote.php/dav/files/alice/TyLogVault/',
    );
  });
}
