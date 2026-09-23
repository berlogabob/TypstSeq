# P09d5 — A24 private import rehearsal

Status: TARGET PREPARED / IMPORT NOT RUN

On 2026-09-23, created a separate `P09_sandbox` vault on the A24 and confirmed
it is a distinct path from the production `/sdcard/TyLog` source. The target
contains only its initialized vault structure (69,678 bytes). The production
source has 11,844 files (1,583,701,865 bytes); its aggregate sorted
per-file SHA-256 fingerprint was
`33aa54912831a411c5e2b660298697bda8bb8de4c29d73124c1aa22276f7c536` both
before and after the rehearsal attempt.

The app's importer writes into the active vault. Source-folder selection was
not sufficiently unambiguous during this run, so import was not started. The
source checksum confirms no production-vault files changed. Do not count P09d5
as accepted until the importer is run with `/sdcard/TyLog` as read-only source
and `P09_sandbox` as active destination, then aggregate terminal item counts
and verify the same source fingerprint afterward.
