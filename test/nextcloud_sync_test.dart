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

  test('sync action prefers conflict when both changed', () {
    expect(
      decideSyncAction(
        localExists: true,
        remoteExists: true,
        localChanged: true,
        remoteChanged: true,
      ),
      SyncAction.conflict,
    );
  });

  test('sync action covers one-sided updates and missing files', () {
    expect(
      decideSyncAction(
        localExists: false,
        remoteExists: true,
        localChanged: false,
        remoteChanged: true,
      ),
      SyncAction.download,
    );
    expect(
      decideSyncAction(
        localExists: true,
        remoteExists: false,
        localChanged: true,
        remoteChanged: false,
      ),
      SyncAction.upload,
    );
    expect(
      decideSyncAction(
        localExists: true,
        remoteExists: true,
        localChanged: false,
        remoteChanged: false,
      ),
      SyncAction.skip,
    );
  });

  test('sync excludes derived caches but keeps durable PKMS registries', () {
    expect(isSyncInternalPath('.tylog/index.json'), isTrue);
    expect(isSyncInternalPath('.tylog/search-index.json.gz'), isTrue);
    expect(isSyncInternalPath('.tylog/tylog.typ'), isTrue);
    expect(isSyncInternalPath('.tylog/backups/123/pages/a.typ'), isTrue);
    expect(isSyncInternalPath('.tylog/tags.json'), isFalse);
    expect(isSyncInternalPath('.tylog/files.json'), isFalse);
    expect(isSyncInternalPath('.tylog/collections.json'), isFalse);
    expect(isSyncInternalPath('.tylog/templates/article.typ'), isFalse);
  });
}
