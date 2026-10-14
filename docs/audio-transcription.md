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
| `lang` | Optional ISO language code (e.g. `en` or `ru`). A non-empty value is passed to faster-whisper; otherwise the worker autodetects. On success, replaced by faster-whisper's detected `info.language`. |
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

Preserve all other job fields when updating its status. After the note write
succeeds, store the detected language in `lang` and add `finished_at`.
Language selection is per job through `lang`; the worker no longer takes
a global `--lang` option.
The worker processes queued translation jobs after transcription jobs, so a
translation can use a transcript written in the same run.

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

## Translation jobs

Path: `_system/jobs/translations/<sha1 of audio + "\n" + target>.json`.
The ID is the lowercase hexadecimal SHA-1 of the exact UTF-8 audio path,
a literal newline, and the target ISO language code, with no trailing newline.
There is one file per (audio, target) pair.

```json
{
  "audio": "audio/recording.wav",
  "note": "notes/recording.typ",
  "target": "ru",
  "source_lang": "en",
  "requested_at": "2026-10-14T12:00:00Z",
  "status": "queued"
}
```

`audio` and `note` are vault-relative paths; `target` and `source_lang` are ISO
language codes. Translation jobs use the same `queued` → `processing` →
`done`/`failed` lifecycle, with optional `finished_at` and `error` fields.
On success the worker adds `finished_at` and removes any old `error`.
On failure it stores descriptive `error` text, preserving the other fields.

The worker reads `- mm:ss text` lines from the existing `== Transcript`
section, unescapes each backslash-prefixed character, and translates the texts.
A missing Transcript section fails the job without changing the note.
The translated section uses the same timestamps and Typst escaping:

```typst
== Translation ru

- 00:00 Первый сегмент.
- 01:23 Следующий сегмент.
```

The heading is exactly `== Translation <target>`. Replace that section if it
already exists; otherwise insert it immediately after the Transcript section,
before the next `== ` section, or append it at the end of the note. Preserve
Comments, Transcript, and every other existing line byte for byte.

Translations use an OpenAI-compatible chat endpoint via Python's standard
library; no extra translation dependency is needed:

| Environment variable | Meaning |
| --- | --- |
| `TYLOG_LLM_URL` | API base URL, including its API prefix, e.g. `http://localhost:1234/v1`. |
| `TYLOG_LLM_KEY` | API key sent as a Bearer token. |
| `TYLOG_LLM_MODEL` | Chat model ID. If unset, use the first model with `loaded: true` from `GET <base>/models`. |

Unset URL/key values fall back individually to `providers.studio.baseUrl` and
`providers.studio.apiKey` in `~/.pi/agent/models.json`. A URL is required; a
keyless local endpoint is supported. The worker sends batches of at most 40
strings to `<base>/chat/completions` at temperature 0, requesting faithful
translation, preserved names, and no commentary. Replies must be JSON arrays
of strings with the same length; surrounding code fences are accepted.

## Sync and failures

The job and note live under synced vault prefixes, so any machine with the
vault can run the worker. Read the audio from that same vault.

On any error, set `status: failed` with descriptive `error` text. Every claimed
job must finish as `done` or `failed`; never leave it in `processing` without
finishing. The app can re-queue a failed job on a later request.

## Running the worker (macOS)

`faster-whisper` 1.2.x breaks with `av` 19 (`open() got an unexpected keyword
argument 'metadata_errors'`); pin `av==17.0.1`:

```
uv run --with faster-whisper --with av==17.0.1 python tool/transcribe_worker.py \
  --vault ~/Nextcloud/TyLogVault --once --model small
```

A launchd agent (`~/Library/LaunchAgents/org.tylog.transcribe.plist`, every
60 s) runs this; its log is `/tmp/tylog-transcribe.log`.
