Write docs/audio-transcription.md: the contract between the TyLog app and a transcription worker. Facts to document (read lib/audio/transcript_jobs.dart, lib/audio/audio_note_doc.dart and lib/article_jobs.dart for the pattern; do not change code):
## Job file: path _system/jobs/transcripts/<sha1 of audio path>.json; fields audio (vault path), note (vault path of the kind:audio note), requested_at (UTC ISO), status queued|processing|done|failed, optional lang, model, finished_at, error. App never resets a claimed or done job; failed is re-queued by the app.
## Worker steps: list jobs, claim by setting status processing, read audio from the vault, transcribe, write the note section, set status done (or failed + error).
## Note format: replace or append the section '== Transcript' with one line per segment '- mm:ss text' (minutes 00-999, seconds 00-59), text escaped for Typst markup (escape \ # [ ] $ * _ @ with a backslash); never touch '== Comments' or any other line; keep the file's existing header bytes.
## Sync: job and note live under synced prefixes, so any machine with the vault can run the worker.
## Failure: on error set status failed with error text; never leave processing without finishing.
Keep it under 80 lines.
