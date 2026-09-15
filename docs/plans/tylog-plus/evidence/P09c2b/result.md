# P09c2b result — resumable batch runner

Accepted 2026-09-15.

The runner validates its stored job against the manifest, processes a deterministic bounded page of pending items, reads note bytes once, and derives progress from stored states. Page and journal writes use the atomic imported-node transaction. Assets, unsupported entries, empty notes, and private-safe source failures receive explicit terminal states. Persistence errors propagate and leave the item pending.

Validation: 7 runner tests cover forced runner recreation, batch bounds, no duplicate nodes/revisions, every source outcome, private-safe failures, manifest/checkpoint corruption, persistence rollback, and terminal-state preservation. The combined import suite has 21 passing tests; targeted analysis reports no issues.
