# P01 — production phone backup and inventory

Date: 2026-09-15. Status: PASS.

The connected Nothing A024 production folder `/sdcard/TyLog` was copied to a new private directory outside the repository. TyLog was force-stopped before the first manifest; the command did not uninstall the package or clear app data.

The backup tool computed a remote SHA256 manifest before transfer, pulled the vault, computed a second remote manifest, and independently hashed the local copy. The coordinator then independently re-read and hashed every copied file and compared it with all three stored manifests.

- Files: 11,826.
- Bytes: 1,539,299,837.
- Before remote manifest = after remote manifest = local manifest.
- Independent second local hash pass: 11,826/11,826 matched.
- Backup directory mode: 0700; manifests and app-settings archive: 0600.
- `verified.json` exists and contains the expected success marker.
- Best-effort app-local settings archive exists. Android Keystore material is not included, so credentials may still require manual entry.

The private backup path, file names, manifests and settings archive are intentionally excluded from Git. This proves the copied snapshot matched the observed phone files during backup; it does not prove historical integrity or authenticate individual note semantics.
