# P01a — Android recovery tool review

Date: 2026-09-14. Status: TOOL ACCEPTED; DEVICE BACKUP PENDING.

Claude CLI version 2.1.270, requested and observed `claude-haiku-4-5-20251001`. CLI reported estimated cost $0.4033325 for the initial implementation. This is reported CLI accounting, not a statement about subscription billing.

Initial draft was not accepted. Coordinator-run tests reported 2 failures and 2 errors; review also found that remote hashing could mask failures, source validation allowed traversal, the full hash manifest was not persisted, and app quiescence failure was ignored. No device command from this tool was executed. The CLI's requested `python` checks were denied by the tool allowlist; coordinator ran the specified `python3` checks directly.

A bounded correction was assigned to Codex Luna. Its turn ended when the model hit a usage limit; the coordinator completed review and final edits in the same two owned tool/test files.

```bash
python3 -m unittest discover -s test/tool -p 'test_backup_android_vault.py' -q
python3 -m py_compile tool/backup_android_vault.py
```

The final suite passed 30 tests. Main-flow tests cover verified success and a changing remote file that retains partial data but cannot create `verified.json`. Other tests exercise absent/truncated local files, safe paths with spaces, unsafe paths, destination checks, missing app settings and remote manifest parsing. A CLI invocation with no ADB device returned a generic failure and created no verified marker. The backup destination is private (mode 0700); full before/after/local hash manifests remain there only.

The app-local settings archive is best-effort and does not include Android Keystore material. Third-party writers can modify the vault while TyLog is stopped; comparing before/after remote hashes detects observed changes. No real device backup occurred: ADB lists no connected device. P01 remains blocked.
