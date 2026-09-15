# P09c2a result — durable import-job initialization

Accepted 2026-09-15.

The database creates the job and all pending manifest items in one transaction and one batch. Repeating the same immutable job identity inserts only missing items while preserving terminal states and progress. Changed fingerprints/counts and incomplete or non-pending manifests fail before any write.

Validation: the focused import database suite has 10 passing tests; targeted analysis reports no issues.
