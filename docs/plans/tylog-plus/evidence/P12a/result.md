# P12a — one maintenance listing per pass

Status: PASS (host)

`VaultMaintenance.run` now captures one immutable recursive vault listing and
passes it through note scanning, Typst inspection-file loading, attachment
validation, and orphan sweeping. Public standalone scanner/validator/sweeper
calls still list normally when no snapshot is supplied.

The counting-storage regression proves the same index, validation, and sweep
results while reducing the maintenance pass to exactly one recursive listing.

```text
dart test                         # packages/tylog_core
210 tests passed

dart analyze lib/src/maintenance.dart lib/src/scanner.dart \
  lib/src/validation.dart test/maintenance_listing_test.dart
No issues found
```

This removes repeated SAF enumeration. It does not yet provide SQLite keyset
pages or move the cached index decode off the root isolate; those are P12b–d.
