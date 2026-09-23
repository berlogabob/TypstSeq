# P09d5 — private A24 import rehearsal

**Result: PASS WITH CONTENT GAPS.** The resumable import reached terminal
accounting for the complete source manifest, passed SQLite integrity checks,
and left the app usable. The acceptance gate for accounting and target
readability is met; conversion completeness is not implied.

## Run

- Device: A24, serial `000251565001005`; app `org.tylog.tylog`, version
  `0.4.4+99`.
- Read-only source: `/sdcard/Logseq`; 3,483 files, 1,463,782,939 bytes before
  and after the run. The importer did not target this directory.
- Separate target: `/sdcard/P09_sandbox`; it was active during import and is
  left registered but unselected for review. The production `/sdcard/TyLog`
  vault was restored as the active vault afterward. No sync was configured or
  run.
- The UI reported “Vault import complete.” The private source was scanned and
  imported in approximately ten minutes.

## Counts and verification

| Measure | Result |
|---|---:|
| Manifest items | 3,483 |
| Terminal items | 3,483 |
| Written / skipped | 1,419 / 2,064 |
| Converted pages / journals | 515 / 904 |
| Empty files skipped | 122 |
| Assets copied / missing | 193 / 16 |
| Unresolved wikilinks | 1,243 |
| SQLite integrity check | `ok` |
| Foreign-key violations | 0 |

The database contained 1,420 nodes and 1,420 revisions (including the target
root). State counts were 2,064 skipped and 1,419 written. No private note text,
file names, or database was committed. The source aggregate file count and byte
size were unchanged; a pre-import content hash was not captured, so this run
does not claim a byte-for-byte source checksum comparison. The post-run
read-only aggregate SHA-256 was
`3ec829fb42fed349ba02ee1cb83f60c71b7fd89f63034b7d31bbb695a077da87`.

## Follow-up

The 16 missing assets and 1,243 unresolved links are recorded as conversion
quality gaps, not as manifest-accounting failures. Review them before treating
the imported sandbox as a complete content migration. The sandbox remains
available on the device; it was deliberately not deleted after verification.
