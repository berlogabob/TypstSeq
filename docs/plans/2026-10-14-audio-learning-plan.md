# Audio + learning modules: delegated work plan (2026-10-14)

Mode: maximum Claude token save. Claude wrote the app code (commit a7bbfe4:
platform peaks decoder, per-file comment notes for any audio chip, transcript
tab, transcript job queue). Everything below is test/doc/worker work that
small models handle. Claude reads one summary table, not diffs of passing runs.

## Run
    tool/audio_plan/run.sh            # all tasks, resumable, no supervision
    tool/audio_plan/report.py         # one line per task

Isolated worktree `../TypstSeq-audio`, branch `plan/audio-learning`. Ornith 1.5
35b (Studio, 64k context) first; a failed ornith task is retried once with
`codex exec -s workspace-write` (low effort). A task lands as one commit only if
its verify command passes AND no file outside its allow list changed.
Rows: `docs/plans/audio-plan-results.jsonl`. Task definitions:
`tool/audio_plan/tasks/<id>/{agent,prompt.md,verify,allow}`.

## Tasks (each one file or two, verify is one command)
| id | owner | output | verify |
|---|---|---|---|
| T01 | ornith | test/audio_peaks_test.dart (bucketPeaks) | flutter test that file |
| T02 | ornith | test/audio_transcript_test.dart (section isolation) | flutter test that file |
| T03 | ornith | test/transcript_jobs_test.dart (job queue rules) | flutter test that file |
| T04 | codex | docs/audio-transcription.md (worker contract) | 4 headings present |
| T05 | codex | tool/transcribe_worker.py + pytest (faster-whisper, lazy import) | uv run pytest |
| T06 | codex | audioAssetNote() extracted + test | analyze + 2 test files |

## Measures
- Landed tasks / 6 (target 6; at least 5 to proceed).
- Ornith first-try pass rate over T01-T03 (target >= 2/3; below that stop using ornith for tests of this kind).
- Stray files outside allow list: target 0 (a stray fails the task).
- Minutes and lines added per task, from the results file.
- Claude involvement before the gate: 0 interventions.

## Gate (Claude, after the run)
1. `git -C ../TypstSeq-audio log --oneline` and skim only failed/escalated runs.
2. Cherry-pick landed commits onto feat/audio-notes-module-packs; run `flutter analyze` and full `flutter test`.
3. Release 0.14.0+139: CHANGELOG, tag, push, upload `pt-pt-a2b1.tylogpack` to the release.
4. User device checks on the A24: record, import mp3 (waveform appears after first open),
   lesson chip -> comments, comment persists after sync, transcript tab shows "Request transcription".

## Not in this plan
Running a real transcription model (needs the worker run on the Studio/Mac after T05);
persisting peaks for the 99 lesson mp3s ahead of time (they backfill on first open).
