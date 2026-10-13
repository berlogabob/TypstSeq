# Audio transcription worker contract

TyLog queues transcription requests as vault files, following the article-job
pattern. A worker reads the audio and updates the existing `kind: audio` note.

## Job file

Path: `_system/jobs/transcripts/<sha1 of audio path>.json`.
The ID is the lowercase hexadecimal SHA-1 of the exact UTF-8 `audio` path string.
All paths below are vault-relative paths.

| Field | Meaning |
| --- | --- |
| `audio` | Vault path of the audio file. |
| `note` | Vault path of the existing `kind: audio` note. |
| `requested_at` | Request time as a UTC ISO 8601 string. |
| `status` | `queued`, `processing`, `done`, or `failed`. |
| `lang` | Optional transcription language. |
| `model` | Optional transcription model. |
| `finished_at` | Optional completion time as a UTC ISO 8601 string. |
| `error` | Optional error text; required when the worker reports failure. |

The app creates jobs with `status: queued`. Re-requesting a queued, claimed
(`processing`), or completed (`done`) job leaves it unchanged. A failed job is
re-queued by the app with a new `requested_at`; optional fields are not retained.

## Worker lifecycle

1. List JSON jobs under `_system/jobs/transcripts/` and select queued jobs.
2. Claim a job by writing `status: processing` to its job file.
3. Read the file at `audio` from the vault and transcribe it.
4. Write the transcript section in the existing file at `note`.
5. After the note write succeeds, set `status: done`.

Preserve the job's required fields when updating its status. The worker may add
`lang`, `model`, and `finished_at`.

## Note format and preservation

Replace the contents of the existing `== Transcript` section, or append that
section if it is absent. An existing section ends at the next line starting
with `== `, or at end of file.

Write one line per segment, using the segment's start time:

```typst
== Transcript

- 00:00 First segment.
- 01:23 Next segment.
```

Each segment line is `- mm:ss text`: minutes range from 00 to 999 (at least two
digits), and seconds from 00 to 59 (exactly two digits). Keep segment text on
one line. Escape each literal `\`, `#`, `[`, `]`, `$`, `*`, `_`, and `@` in the
text by prefixing it with a backslash; a literal backslash becomes `\\`.

Never touch `== Comments` or any line outside the transcript section. Preserve
the file's existing header bytes exactly; do not regenerate or reformat the
note header, attachment, or other sections.

## Sync and failures

The job and note live under synced vault prefixes, so any machine with the
vault can run the worker. Read the audio from that same vault.

On any error, set `status: failed` with descriptive `error` text. Every claimed
job must finish as `done` or `failed`; never leave it in `processing` without
finishing. The app can re-queue a failed job on a later request.
