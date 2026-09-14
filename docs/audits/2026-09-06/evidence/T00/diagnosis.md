# T00 device crash diagnosis

Selecting the empty `TyLogAuditVault` folder entered `_openVault` twice. The
initial `_pickVault(closeCurrent: false)` already selected and opened the new
entry; `_open()` then continued to its common startup path and opened the same
entry again. The second open killed the first worker while its SAF requests
were still pending. The native `SafBridge` later posted a `MethodChannel.Result`
to that worker's closed Dart response port, causing Flutter's fatal
`platform_message_response_dart_port.cc:53` `did_send` check.

The startup path now completes onboarding and returns after the successful
pick, so the common open path runs only once. Failure behavior is unchanged.
