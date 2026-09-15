# P09c1 result — atomic imported-node materialization

Accepted 2026-09-15.

`commitImportedNode` validates the node, revision, job, and import item, then writes the node, immutable revision, outbox entry, derived invalidation, terminal item, and job progress in one Drift transaction. It reuses the same row-writing path as ordinary node edits.

Validation: the focused database suite has 7 tests. The success case observes every related row; an invalid progress update rolls all new rows back and leaves the job unchanged.
