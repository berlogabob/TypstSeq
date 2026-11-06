# 2026-11-04 note write corruption

## Evidence and limits

On 2026-11-04 at 01:19, `daily/2026/11/2026-11-02.typ` contained a revision envelope instead of note text. The incident record ties that time to task `20261102-095848` changing from doing to done and its clock stopping at 01:19:10. The previous note text was recovered from `node.content`. The P30 log buffer no longer reaches the incident, so it cannot identify the process or call site. The Mac GUI was locked during this investigation. The P30 production package was reported absent on 2026-11-06, so its required `firstInstallTime` could not be checked without violating the device constraint; no device was touched.

## Write-path audit

All app note writes that use `VaultStorage` converge on `writeBytes` or `appendBytes` in `lib/vault_storage.dart` (SAF) and `packages/tylog_core/lib/src/storage.dart` (local). Both call `guardNoteWrite` against the exact bytes before persistence. Text writes delegate to bytes. Local appends validate the existing bytes plus the new bytes before opening the append sink. SAF appends validate the existing bytes plus the addition before the provider append, and validate the combined bytes again on the provider read/write fallback. Android imports use `importPlatformFile` and validate the source bytes before the native import/write channel. Native `SafBridge` persists those already-validated bytes atomically; it is not an independent note-content producer. Sync downloads, conflict choices, revision winners, restore, and in-app note saves call the same storage write methods. Sidecars and managed `.typ` files under `_system/`, `_index/`, and `.tylog/` are intentionally outside the note guard.

## Regression coverage

`test/vault_storage_test.dart` covers local and SAF direct writes, rejection while preserving the existing note, append validation, SAF provider fallback, late SAF write/append outcomes, and acceptance of legacy JSON-shaped notes. Its import test verifies the exact bytes sent and proves rejection happens before a native call. Together these exercise both storage implementations and the app-level native import entry point; sync and conflict producers inherit the guard through those same storage methods. `test/vault_test.dart` covers the vault note-save path. The guard is deliberately signature-based because valid headerless and JSON-shaped legacy Typst notes exist; less distinctive JSON remains writable.

## Conclusion

The surviving evidence does not establish which runtime or producer caused the original cross-path write. The current implementation prevents the observed revision-envelope class from replacing note text at the shared persistence boundary, while retaining valid legacy note text. No device evidence was needed to complete this write-path audit.
