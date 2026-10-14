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
| `langs` | On success, the detected language list, with dominant `lang` first. A forced `lang` produces `[lang]`. |
| `model` | Optional transcription model. |
| `finished_at` | Optional completion time as a UTC ISO 8601 string. |
| `error` | Optional error text; required when the worker reports failure. |

The app creates jobs with `status: queued`. Re-requesting a queued, claimed
(`processing`), or completed (`done`) job leaves it unchanged. A failed job is
re-queued by the app with a new `requested_at`; optional fields are not retained.

## Worker lifecycle

1. Sweep eligible audio notes according to the settings and local state below,
   then list JSON jobs under `_system/jobs/transcripts/` and select queued jobs.
2. Claim a job by writing `status: processing` to its job file.
3. Read the file at `audio` from the vault and transcribe it.
4. Write the transcript section in the existing file at `note`.
5. After the note write succeeds, set `status: done`.

Preserve all other job fields when updating its status. After the note write
succeeds, store the dominant language in `lang`, the language list in `langs`,
and add `finished_at`.
Language selection is per job through `lang`; the worker no longer takes
a global `--lang` option.
The worker processes queued translation jobs after transcription jobs, so a
translation can use a transcript written in the same run.

Without a forced language, transcription uses `multilingual: true`. After
transcribing, the worker decodes the audio once at 16 kHz and detects the
language of each 30-second window containing segments, grouping segments by
their start time. Each detected language is weighted by the summed segment
duration in its windows. Languages with at least 15% of total speech time are
retained in descending weight order, with the dominant `info.language` always
included first. Detection failure falls back to `[lang]`. A forced language
skips this detection and returns only that language.

## Automatic sweep

The synced settings file is `<vault>/_system/settings/processing.json`:

```json
{
  "schema": 1,
  "audio": {
    "transcribe": true,
    "translate": true,
    "on_the_fly": false,
    "scheduled": true,
    "time": "03:00",
    "translate_to": ["ru", "en", "pt"]
  }
}
```

`transcribe` enables automatic transcription jobs. `translate` independently
enables automatic translation jobs when `translate_to` is non-empty. If
`translate` is missing, it defaults to `bool(translate_to)`. Missing settings
disable both features. Already queued jobs still run regardless of these flags.
`translate_to` contains ISO language codes. With `transcribe: false` and
`translate: true`, existing transcripts (including ones written by hand) can
still be translated, provided their transcription job records the source
language metadata described below.

Each worker invocation starts with a sweep. Its gate opens when `on_the_fly`
is true, or when `scheduled` is true and the current local time has reached
today's `time` (24-hour `HH:MM`) without a completed scheduled sweep today.
This catches up after sleep: waking at 09:00 still runs a 03:00 sweep. A due
scheduled run stays open on every invocation until a sweep creates no jobs and
no job is `queued` or `processing`; only then does it record the local date as
`last_scheduled_date`. This lets transcripts finish and their translations be
created the same night. With both modes enabled, on-the-fly sweeps continue
after that day's scheduled run.

For manual **process now**, write `<vault>/_system/jobs/process-now.json`:

```json
{"requested_at": "2026-10-14T12:00:00Z"}
```

A `requested_at` different from state `last_process_now` forces the sweep gate
open once, then records that value. The worker leaves the request file in
place; use a new timestamp for a new request. This bypasses the time gate but
still respects the independent `audio.transcribe` and `audio.translate` flags.

Local worker state is JSON at `~/.tylog-transcribe-state.json` by default.
Override it with `--state <path>` (or `run_once(..., state_path=...)`). Missing
or corrupt state is treated as empty. The state stores `last_scheduled_date`
and `last_process_now`; keep it local and use a separate file per vault.

The sweep scans `notes/Audio *.typ`, requiring `kind: "audio"` in the note
header and an audio attachment of the form
`#tylog.attachment("<path>", kind: "audio")`. It unescapes backslash-prefixed
characters, strips leading slashes, and skips missing audio files or paths
outside the vault.

- A missing or whitespace-only `== Transcript` section queues a transcription
  job only when `transcribe` is true, unless its SHA-1 job file already exists
  in any status.
- A non-empty Transcript section plus `lang` in its transcription job permits
  translation jobs when `translate` is true, using `langs` as the source
  language list. Missing `langs` falls back to `[lang]` for older jobs.
  A monolingual transcript with `langs: [L]` is already the complete version
  in L, so it skips target L and translates into the other selected languages.
  A mixed transcript with more than one language creates jobs for every
  selected target, including its dominant language, so speech in the other
  languages is translated too. For example, `langs: ["pt", "ru"]` with
  `translate_to: ["ru", "en", "pt"]` creates all three translation jobs.
  An existing `== Translation <target>` heading (even empty) or an existing
  translation job file blocks creation for that target.
- Sweep jobs use the formats below with `auto: true` and `status: "queued"`.
  Existing jobs, including `failed` jobs, are never re-created by the sweep;
  retry failed jobs through the app.

Jobs created by the sweep are processed in the same invocation. Transcripts
completed during that invocation become eligible for automatic translations
on the next sweep (the next minute: the scheduled run stays open until all
jobs are finished, see above).

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
  "source_langs": ["en", "pt"],
  "requested_at": "2026-10-14T12:00:00Z",
  "status": "queued"
}
```

`audio` and `note` are vault-relative paths; `target` and `source_lang` are ISO
language codes. `source_lang` is the dominant language; `source_langs` lists
the transcript's languages and defaults to `[source_lang]` when missing.
Sweep jobs copy these from the transcription job's `lang` and `langs`.
Translation jobs use the same `queued` → `processing` →
`done`/`failed` lifecycle, with optional `finished_at` and `error` fields.
On success the worker adds `finished_at`, records the model actually used in
`llm`, and removes any old `error`.
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
| `TYLOG_LLM_MODEL` | Explicit chat model ID, used exactly as supplied; overrides automatic selection. |
| `TYLOG_LLM_PREFER` | Preferred chat model ID when `TYLOG_LLM_MODEL` is unset; defaults to `ollama/ornith-1.5:35b`. |

Automatic selection first uses a loaded model whose ID exactly matches the
preferred ID, then a loaded model whose ID contains `ornith` (case-insensitive).
If neither is loaded, the worker resolves the preferred model's Studio reference
ID through `GET <root>/api/models/local` and sends `POST <root>/load` with
`model_path` and `max_seq_length: 65536`, without `force_cancel_active`.
Here `<root>` is the base URL with its `/v1` suffix removed. It polls
`GET <base>/models` for up to 15 minutes until the preferred model is loaded.
Loading errors or timeout fail the job with an error naming the preferred model;
the worker never silently falls back to an unrelated loaded model such as Qwen.

Unset URL/key values fall back individually to `providers.studio.baseUrl` and
`providers.studio.apiKey` in `~/.pi/agent/models.json`. A URL is required; a
keyless local endpoint is supported. The worker sends batches of at most 40
strings to `<base>/chat/completions` at temperature 0, requesting faithful
translation into the target, preserved names, and no commentary. The prompt
lists `source_langs` as potentially mixed source languages and requires
segments already in the target language to be returned unchanged. This
produces a complete target-language version while preserving those segments.
Replies must be JSON arrays
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
