# P02 — restore production vault and normal release

Date: 2026-09-15. Status: PASS.

After P01 verification, Flutter produced the normal release APK and `adb install -r` installed it over the existing profile package. No uninstall or clear-data command was used.

- Package: `org.tylog.tylog`, version `0.4.4+99`.
- Package flags no longer include `DEBUGGABLE`.
- Android Storage Access Framework was used to add and select the existing root-level `TyLog` folder.
- The initial production scan reached 6,299 notes; the prior raw inventory contained 6,305 `.typ` files, including system/non-note sources.
- Production content was visible and the audit fixture marker was absent.
- Cold restart reported `Status: ok`, Android `TotalTime: 263 ms`; no folder-access dialog appeared and production content remained visible.
- The cached startup refresh indicator cleared within the next 12 seconds. This is a single observation, not a p95 performance claim.

The app reports sync as not connected. P03 remains open and requires real bidirectional Nextcloud evidence.
