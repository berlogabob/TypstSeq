Edit ONE file, lib/workspace_controller.dart (about 2,500 lines). Do not modify or create any other file. Do not rewrite the file: change only the function named below, with a targeted edit.

Near the end of the file is the top-level function `String friendlySyncError(Object error)`.
Add a new FIRST branch to it: when `error` is a `WebDavStatusException` whose `statusCode` is 502, 503, 504, or anything from 520 to 530 inclusive, return exactly

    Nextcloud server is unreachable (<code>). Your notes are saved on this device; sync will retry.

where `<code>` is the status code. `WebDavStatusException` is already visible in this file (it has an `int statusCode` field). Every other input must return what it returns today.

`flutter analyze --no-pub lib/workspace_controller.dart` must report no issues.
