# T04 result

Status: DONE

T04 now pauses automatic polling after WebDAV 401/403 until credentials change
or an explicit retry. Transient failures use fake-time backoff of 25, 50, 100,
200, then 300 seconds; success resets the schedule. The single-flight guard
keeps an in-flight poll from overlapping another attempt. Definitive typed HTTP
status errors make one request instead of entering the connection retry loop.

Verification:

- `flutter test test/workspace_controller_test.dart --plain-name 'poll pauses rejected credentials until config changes or retry runs'`: 1 passed.
- `flutter test test/workspace_controller_test.dart --plain-name 'poll backoff grows to five minutes and resets after success'`: 1 passed.
- `flutter test test/workspace_controller_test.dart`: 38 passed.
- `flutter test test/vault_worker_test.dart`: 6 passed.
- `flutter analyze lib/workspace_controller.dart lib/nextcloud_sync.dart lib/nextcloud_sync/webdav_client.dart test/workspace_controller_test.dart`: no issues.
- `git diff --check`: passed.

The focused auth test covers 401 and 403, config reset, explicit retry, and
blocked automatic `setup`, `resume`, and `autosave` triggers. The backoff test
freezes all five delays and checks the cap and reset.

SHA-256 (working-tree files):

- `lib/workspace_controller.dart` 57129edbfac7db55acb31ba6b2cf6d58bdff024ac5fd1a669d14900e7423defd
- `lib/nextcloud_sync.dart` 2ce724efab98d8847a2ef36d9d3450c29df2f7c673facd21b58c72c7fd94b514
- `lib/nextcloud_sync/webdav_client.dart` ff1cbee70c55bf114120d974dde47affc13828a2c7b109d7cf72516f7a506f4a
- `test/workspace_controller_test.dart` 63ac37a925af9a0e9108cdc0380ce9637db388f37823cdd60d296135c41281a2

Scoped diff SHA-256 for the four files above: `841684bec8fa8e9c2f61624912ae2c0ba0da1bef7aa8a04af552a9fbbe42f8cf`.

Limitations: device validation remains outside T04; existing sync error stack
output is expected during the failure-path tests.
