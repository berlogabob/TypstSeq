# T00 connected-phone profile result

Date: 2026-09-09
Status: COMPLETE WITH NETWORK LIMITATION

The release-signed profile build (`0.4.4+99`) ran on a Nothing A024, Android
16 / SDK 36. The isolated `TyLogAuditVault` fixture ended with 2,016 files and
3,239,237 bytes; 2,001 entries were present during the measured index runs.

- First populated index: 54 seconds, 2,001 indexed entries, process alive, no
  fatal Android or late platform-response error.
- Repeated cold display: 440 ms, 633 ms, and 894 ms. A later final normal-build
  cold launch was 745 ms.
- Warm real-vault rebuild: 6 seconds. Inline work dropped 6 root-isolate frames
  with a 63 ms worst gap; the worker dropped 3 with a 35 ms worst gap.
- Five-minute settled observation: 303 seconds, live process, unchanged
  `index.json` and `search-index.json.gz` metadata, and no fatal error. This is
  zero repeated idle content scans.

The disposable vault had no Nextcloud account, so an authentic remote sync
completion time and rejected production credentials were unavailable. The
device sync-attribution, foreground-service, and controlled 401/403 results are
recorded under T28/T04. No pre-fix phone timing exists, so this evidence makes
no before/after percentage claim.
