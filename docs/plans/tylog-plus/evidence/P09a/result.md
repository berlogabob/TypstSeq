# P09a result — durable import checkpoints

Accepted 2026-09-15 at schema version 5.

- `import_jobs` persists source identity, lifecycle, and bounded progress.
- `import_items` persists one state per `(job_id, source_path)` and cascades with its job.
- Item state and job progress update in one transaction; a forced constraint failure rolls both back.
- Fresh creation and v4→v5 migration preserve prior data.
- The composite primary key supplies the job/path index; only the job/state query needs a separate index.

Validation: 13 focused database tests pass, and targeted Flutter analysis reports no issues.
