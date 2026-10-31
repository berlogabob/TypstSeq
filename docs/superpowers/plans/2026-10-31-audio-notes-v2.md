# Audio notes v2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn a long noisy recording into a faithful sentence-level transcript with non-speech marked, doubtful places flagged, and the text present in ru, en and pt, without ever overwriting the user's edits.

**Architecture:** `tool/transcribe_worker.py` keeps its job queue; a new module `tool/audio_v2.py` holds the pure pieces (speech map, hallucination filter, sentence split, sidecar merge). The worker cuts audio on voice activity, sends chunks to two Studio STT engines, keeps per-line data in a sidecar `_system/jobs/segments/<sha1(audio)>.json`, and renders note sections from it with edit protection.

**Tech Stack:** Python 3 (worker venv `~/.tylog/venvs/transcribe`, `faster_whisper` already installed, its bundled Silero VAD), ffmpeg, Unsloth Studio HTTP API, Dart (`lib/audio/audio_note_doc.dart`).

**Spec:** `docs/superpowers/specs/2026-10-31-audio-notes-v2-design.md`

## Global Constraints

- Python via `uv` only. Worker tests: `uv run --with pytest --with faster-whisper --with av==17.0.1 --with scikit-learn pytest tool/test_transcribe_worker.py tool/test_audio_v2.py -q` (never piped through `tail`; read the exit code).
- Models run on Studio only: `http://desktop-vdsrh2e:8888`, key = `~/.pi/agent/models.json` `providers.studio.apiKey`. The Mac never loads a model larger than `small`, never starts a model when free memory < 4 GB, and runs the fallback under `nice -n 19`. The Mac has frozen and shut down under load; this is a hard rule.
- Never start or install oMLX. Never `svc power stayon`.
- Every HTTP call has a hard wall-clock deadline (`with deadline(seconds):`), not only a socket timeout.
- Text in all of ru, en, pt for every recording (source = Transcript, others = `== Translation <lang>`); not switchable off.
- Tests never touch `~/Nextcloud/TyLogVault`; only Task 9 runs on the real vault, after copying the baseline note.
- One commit per task; message ends with the session's attribution lines.
- Escape transcript text with the existing `escape_markup`; markers: non-speech line text `[—]`, doubtful prefix `(?) `.

## Review Focus

1. Recording with no speech at all (music only) -> note gets `[—]` lines only, job `done`, not `failed`. Test in Task 7.
2. Studio unreachable or a request hangs mid-job -> deadline fires, job resumes from the sidecar next run; Mac fallback respects the memory guard. Tests in Task 1 and Task 7.
3. User edits a transcript line while the job runs -> edit survives (note is re-read right before each write). Test in Task 6.
4. Recording shorter than one VAD chunk (< 5 s) -> one line, no crash. Test in Task 3.
5. Typst-special characters (`# [ ] $ * _ @`) in recognised text -> escaped, round-trips through `parseTranscript`. Test in Task 6.

## Executors

Haiku subagents for tasks 1-8 (each commits only its own files: `git commit -- <paths>`). Pure-function tasks (2, 4, 5, 8) may go to pi + `ollama/ornith-1.5:35b` instead, but only while the Studio GPU is not busy with STT (Task 3, Task 9). Task 9 and the phase gate: Claude, reading only the metric table and failures.

---

## Phase 0: baseline and probes

### Task 1: Hard deadline on HTTP calls; guarded Mac fallback

**Files:**
- Modify: `tool/transcribe_worker.py` (`transcribe_studio`, `translate.request`, `run_once` fallback branch)
- Test: `tool/test_transcribe_worker.py`

**Interfaces:**
- Produces: `deadline(seconds: float)` context manager in `tool/transcribe_worker.py` (uses `signal.setitimer(signal.ITIMER_REAL, ...)`, raises `TimeoutError`, restores the previous handler); `mac_fallback_allowed(free_bytes: int | None = None) -> bool` (free memory from `vm_stat` when `free_bytes` is None; True only if >= 4 GiB).

- [ ] **Step 1: Write the failing tests**

```python
def test_deadline_interrupts_a_blocking_call():
    import time
    with pytest.raises(TimeoutError):
        with worker.deadline(0.2):
            time.sleep(5)

def test_studio_post_that_hangs_is_cut_by_deadline(tmp_path, monkeypatch):
    # post never returns; transcribe_studio must raise TimeoutError within ~deadline
    ...  # fake post = lambda req, timeout: time.sleep(10); monkeypatch worker.STUDIO_DEADLINE = 0.3

def test_mac_fallback_refused_when_memory_low():
    assert worker.mac_fallback_allowed(free_bytes=2 * 1024**3) is False
    assert worker.mac_fallback_allowed(free_bytes=6 * 1024**3) is True

def test_local_fallback_caps_model_at_small(...):
    # run_once with Studio failing and settings model "large-v3": transcribe() is called with model="small"
```

- [ ] **Step 2: Run, expect FAIL** (`deadline` / `mac_fallback_allowed` undefined).
- [ ] **Step 3: Implement.** `STUDIO_DEADLINE = 600` per chunk request, `LLM_DEADLINE = 900`; wrap every `post(...)`/`urlopen(...)` in `deadline(...)`. In `run_once`, when falling back to local: if `not mac_fallback_allowed()` set job `failed` with error `"Studio unreachable; Mac fallback refused (low memory)"`; else call `transcribe` with `model=min_model(model, "small")` and `os.nice(19)` once per process.
- [ ] **Step 4: Run the worker tests, expect PASS (all, not only new).**
- [ ] **Step 5: Commit** `Transcribe worker: hard deadline on Studio calls, guarded Mac fallback (small model, 4 GB free)`.

### Task 2: Metrics script

**Files:**
- Create: `tool/audio_metrics.py`
- Test: `tool/test_audio_v2.py` (first tests in the file)

**Interfaces:**
- Produces: `note_metrics(note_text: str) -> dict` with keys `lines, loops, mid_cut, nonspeech, doubtful, translations` where `translations = {lang: {"lines": int, "untranslated": int, "failed": int}}`; CLI `uv run --no-project python tool/audio_metrics.py <note.typ>` prints the dict as one JSON line.

- [ ] **Step 1: Failing tests** using a 6-line fixture string:

```python
def test_metrics_counts_baseline_error_classes():
    m = audio_metrics.note_metrics(FIXTURE)
    assert m["lines"] == 6
    assert m["loops"] == 1          # "Não, não, não, ..." x40
    assert m["mid_cut"] == 2        # lines not ending in . ! ? … " »
    assert m["nonspeech"] == 1      # "[—]"
    assert m["doubtful"] == 1       # starts with "(?) "
    assert m["translations"]["ru"] == {"lines": 6, "untranslated": 2, "failed": 0}
```
  Loop = > 20 words and unique/total < 0.25. Untranslated (ru) = < 5 Cyrillic letters and not a marker; (en, pt) = line equal to the transcript line at the same index. `failed` = `[sem tradução]`.
- [ ] **Step 2: Run, expect FAIL.**
- [ ] **Step 3: Implement** with `parse` logic mirroring `_parseSection` in `lib/audio/audio_note_doc.dart` (regex `^\s*-\s+(\d{1,3}):([0-5]\d)\s+(.+?)\s*$`, section ends at next `== `).
- [ ] **Step 4: Run, expect PASS.** Then run on the real note read-only and save the line to `docs/plans/audio-v2-metrics.jsonl` as `{"phase": "baseline", ...}`. Expected roughly `lines 205, loops 40, mid_cut 51`.
- [ ] **Step 5: Commit** `Audio metrics script + baseline row`.

### Task 3: STT engine bake-off on Studio (probe + decision)

**Files:**
- Create: `tool/asr_bakeoff.py` (kept; reused to re-test engines later)
- Output: `docs/plans/audio-v2-asr-bakeoff.md` (table + decision, <= 40 lines)

**Interfaces:**
- Produces for Task 7: the exact request shape that works for the chosen engines (endpoint, JSON or multipart fields, how audio is passed, whether `timestamps: true` returns word times), written in the bake-off doc under "Client contract".

- [ ] **Step 1:** Read `GET /openapi.json` schemas for `TranscribeRequest`, `/api/inference/audio/inputs`, `/api/inference/audio/transcribe/source`, `/api/inference/audio/stt/download`, `/api/inference/audio/stt/load`; write the client contract.
- [ ] **Step 2:** Download (via `stt/download`, poll `stt/status`) Whisper `large-v3` (transformers), `qwen3-asr-1.7b` (mtmd), `Parakeet-TDT-0.6B-v3` (audiocpp). One at a time; unload after use (`stt/unload`).
- [ ] **Step 3:** Clips (mono 16 kHz, from `assets/Friday at 21-17.aac`): speech 06:00-06:30, 18:30-19:00, 22:30-23:00, 23:00-23:30; music/loop 02:00-02:30, 03:00-03:30, 04:30-05:00; short 05:00-05:05. Run each engine (plus current large-v3-turbo) with `language=pt`; record text, seconds, timestamps returned yes/no.
- [ ] **Step 4:** Table per engine: loop/garbage on the 3 music clips (count), credit hallucinations, pairwise word agreement on speech clips (`difflib.SequenceMatcher` ratio on lowercased words), seconds per 30 s clip, timestamps. Decision rule: primary = fewest garbage on music clips, tie -> highest mean agreement with the other engines; secondary = best of the rest with a different architecture (Whisper vs non-Whisper).
- [ ] **Step 5: Commit** `ASR bake-off on Studio: engines, client contract, decision`.

## Phase 1: clean transcript

### Task 4: Speech map from VAD

**Files:**
- Create: `tool/audio_v2.py`
- Test: `tool/test_audio_v2.py`

**Interfaces:**
- Produces: `plan_chunks(speech: list[tuple[float, float]], total: float, max_len: float = 25.0, mark_gap: float = 5.0) -> list[dict]` returning ordered items `{"start", "end", "kind": "speech" | "gap"}`; `speech_regions(audio_path) -> list[tuple[float, float]]` (thin wrapper: `faster_whisper.decode_audio` + `faster_whisper.vad.get_speech_timestamps`, seconds).

- [ ] **Step 1: Failing tests** (pure `plan_chunks` only):

```python
def test_regions_merge_up_to_25s_and_split_at_longest_pause():
    speech = [(0, 10), (10.5, 20), (22, 30), (30.2, 40)]
    items = plan_chunks(speech, total=40)
    assert [(i["start"], i["end"]) for i in items if i["kind"] == "speech"] == [(0, 20), (22, 40)]

def test_long_gap_becomes_gap_item_short_gap_does_not():
    items = plan_chunks([(0, 5), (12, 15), (16, 20)], total=20)
    assert [i["kind"] for i in items] == ["speech", "gap", "speech"]

def test_single_region_longer_than_max_is_split_evenly():
    items = plan_chunks([(0, 60)], total=60)
    assert all(i["end"] - i["start"] <= 25 for i in items) and items[-1]["end"] == 60

def test_short_recording_one_chunk():
    assert plan_chunks([(0.3, 3.9)], total=4.2) == [{"start": 0.3, "end": 3.9, "kind": "speech"}]

def test_no_speech_is_one_gap():
    assert plan_chunks([], total=300) == [{"start": 0, "end": 300, "kind": "gap"}]
```
- [ ] **Step 2: Run, expect FAIL.**
- [ ] **Step 3: Implement.** Greedy merge while the merged span <= `max_len`; a span over `max_len` with no pause is cut into equal parts <= `max_len`; gaps >= `mark_gap` between kept chunks (and at start/end) become `gap` items.
- [ ] **Step 4: Run, expect PASS.**
- [ ] **Step 5: Commit** `Audio v2: speech map (VAD regions -> chunks <= 25 s, long gaps marked)`.

### Task 5: Hallucination filter and sentence lines

**Files:**
- Modify: `tool/audio_v2.py`
- Test: `tool/test_audio_v2.py`

**Interfaces:**
- Produces: `is_hallucination(text: str) -> bool`; `sentence_lines(start: float, end: float, text: str) -> list[tuple[float, str]]`.

- [ ] **Step 1: Failing tests** (strings taken from the baseline note):

```python
@pytest.mark.parametrize("text", [
    "É isso aí! " * 40, "Não, " * 80, "A CIDADE NO BRASIL " * 30, "." * 300,
    "Legenda por Sônia Ruberti", "Legendas pela comunidade Amara.org", "Obrigado.",
])
def test_garbage_is_flagged(text): assert is_hallucination(text)

@pytest.mark.parametrize("text", [
    "Nasci no seio de uma família muito respeitada.",
    "Não, não. O que quer dizer? Vai com calma.",
])
def test_speech_is_kept(text): assert not is_hallucination(text)

def test_sentences_get_proportional_times_and_short_ones_join():
    lines = sentence_lines(100.0, 120.0, "Toda. Menos. Eu. A minha família comunica muito através do humor.")
    assert lines[0] == (100.0, "Toda. Menos. Eu.")
    assert lines[1][0] > 100.0 and lines[1][1].startswith("A minha")

def test_text_without_punctuation_is_one_line():
    assert sentence_lines(5.0, 9.0, "olá a todos") == [(5.0, "olá a todos")]
```
  Rules: zlib compression ratio of the UTF-8 text > 2.4 (only when len > 40); blocklist regex `(?i)^(legendas?\b|subtitles? by|amara\.org|obrigad[oa]\.?$)`; `collapse_repeats` from the worker changing the text by > 50%. Sentences split after `.!?…` followed by space; a sentence of < 3 words joins the next (the last joins the previous); time = start + (end-start) * char_offset/len(text).
- [ ] **Step 2-4:** FAIL, implement, PASS.
- [ ] **Step 5: Commit** `Audio v2: hallucination filter and sentence lines`.

### Task 6: Sidecar and edit-protected rendering

**Files:**
- Modify: `tool/audio_v2.py`
- Modify: `lib/audio/audio_note_doc.dart:89-104` (stable order: sort by `(ms, index)`)
- Test: `tool/test_audio_v2.py`, `test/audio_transcript_test.dart`

**Interfaces:**
- Consumes: `escape_markup`, `format_ts` from `tool/transcribe_worker.py` (import, don't copy).
- Produces: `sidecar_path(vault: Path, audio: str) -> Path` (= `vault/_system/jobs/segments/<sha1(audio)>.json`); `load_sidecar(path) -> dict` (`{"lines": [], "stages": {}}` when missing); `save_sidecar(path, data)` (write tmp + `os.replace`); `merge_section(note_text: str, heading: str, lines: list[dict]) -> tuple[str, list[dict]]`. A line dict: `{"start": float, "kind": "speech"|"gap", "text": str, "status": "ok"|"doubtful"|"user"|"deleted", "rendered": dict[str, str]}`; `rendered[heading]` is the exact note line last written.

- [ ] **Step 1: Failing tests**

```python
def test_untouched_lines_are_rewritten(): ...      # note line == rendered -> replaced by new text
def test_edited_line_is_kept_and_marked_user(): ...  # same mm:ss, different text -> kept, status "user"
def test_deleted_line_stays_deleted(): ...           # rendered absent, no same-ts line -> status "deleted", not re-added
def test_user_added_line_is_kept_in_time_order(): ...
def test_two_lines_same_second_keep_order(): ...
def test_special_chars_escaped_and_parse_back(): ... # "#tag [x] $5 *a* _b_ @c" -> escaped in note
def test_legacy_section_without_sidecar_is_backed_up_then_replaced(tmp_path): ...  # writes <hash>.v1.typ
```
  Dart: `test('same-second segments keep file order', ...)` in `test/audio_transcript_test.dart`.
- [ ] **Step 2: Run, expect FAIL.**
- [ ] **Step 3: Implement.** Match note lines to sidecar lines by exact `rendered[heading]`; unmatched sidecar line with an unclaimed note line at the same `mm:ss` = edited (take the note text, unescape, status `user`); unmatched with no such note line = `deleted`; leftover note lines = user-added (`status "user"`, inserted by time). Output section = non-deleted lines sorted by `(start, original index)`, `- mm:ss text` with `(?) ` prefix for `doubtful`, `[—]` for `gap`. Section placement as `apply_transcript` does today.
- [ ] **Step 4: Run Python and `flutter test test/audio_transcript_test.dart`, expect PASS.**
- [ ] **Step 5: Commit** `Audio v2: sidecar + edit-protected section rendering; stable same-second order in Dart`.

### Task 7: Wire v2 transcription into the worker

**Files:**
- Modify: `tool/transcribe_worker.py` (`run_once` transcript branch, `sweep` targets)
- Create in `tool/audio_v2.py`: `studio_stt(...)` per the Task 3 client contract
- Test: `tool/test_transcribe_worker.py`

**Interfaces:**
- Consumes: `plan_chunks`, `speech_regions`, `is_hallucination`, `sentence_lines`, `merge_section`, `load_sidecar`, `save_sidecar`, `deadline`, Task 3 decision (primary, secondary engine ids).
- Produces: `transcribe_v2(audio: Path, vault: Path, job: dict, stt: Callable[[Path, str], str], sidecar: Path) -> list[dict]` (lines, also saved; resumes: chunks already in `sidecar["chunks"]` are not re-sent); `translation_targets(source_langs: list[str], settings_targets: list[str]) -> list[str]` = `["ru","en","pt"]` minus sources, plus extra settings targets, order kept.

- [ ] **Step 1: Failing tests**

```python
def test_v2_marks_music_chunks_and_keeps_speech(tmp_path): ...    # fake stt returns loop text for chunk 2 -> gap line
def test_v2_resumes_from_sidecar_without_resending(tmp_path): ... # sidecar has 3 of 5 chunks -> stt called twice
def test_v2_all_music_recording_is_done_not_failed(tmp_path): ...
def test_v2_secondary_engine_text_stored_as_asr_alt(tmp_path): ...
def test_note_reread_before_write_keeps_midrun_edit(tmp_path): ...
def test_three_languages_always_enqueued():
    assert translation_targets(["pt"], ["ru"]) == ["ru", "en"]
    assert translation_targets(["ru"], []) == ["en", "pt"]
    assert translation_targets(["es"], ["de"]) == ["ru", "en", "pt", "de"]
```
- [ ] **Step 2: Run, expect FAIL.**
- [ ] **Step 3: Implement.** Transcript job: `speech_regions` -> `plan_chunks` -> for each speech chunk: ffmpeg-cut wav, primary `stt` (under `deadline`), filter; secondary `stt` stored as `asr_alt` (used in Phase 2); save sidecar after every chunk; then `sentence_lines` -> `merge_section(..., "Transcript", ...)` on a fresh read of the note. `sweep` uses `translation_targets` instead of `targets`. v1 `transcribe_studio` stays as the path when the job has `"engine": "v1"`.
- [ ] **Step 4: Run all worker tests, expect PASS.**
- [ ] **Step 5: Commit** `Transcribe worker: v2 path (VAD chunks, two Studio engines, sidecar, sentence lines); ru/en/pt always`.

### Task 8: Translation lines follow transcript lines

**Files:**
- Modify: `tool/transcribe_worker.py` (`apply_translation`)
- Test: `tool/test_transcribe_worker.py`

**Interfaces:**
- Consumes: `merge_section`, sidecar lines.
- Produces: translations written through `merge_section(note, f"Translation {lang}", ...)`, one line per transcript line, same `start`; `gap` lines copied as `[—]`, never sent to the model; a line that fails both batch and single retry is `[sem tradução]`, not the source text.

- [ ] **Step 1: Failing tests:** `test_gap_lines_not_sent_to_model`, `test_failed_line_is_marked_not_source`, `test_translation_line_count_equals_transcript`, `test_user_edited_translation_line_kept`.
- [ ] **Step 2-4:** FAIL, implement, PASS.
- [ ] **Step 5: Commit** `Translation: one line per sentence, gaps copied, failures marked`.

### Task 9: Run on the theatre recording (Claude)

- [ ] Copy `notes/Audio Friday at 21-17.typ` to `_system/jobs/segments/<hash>.v1.typ` (Task 6 does this; verify it exists).
- [ ] Queue the transcript job with `"engine": "v2"`, run the worker once by hand; then translations en, ru.
- [ ] `tool/audio_metrics.py` on the note -> append `{"phase": "1", ...}` to `docs/plans/audio-v2-metrics.jsonl`.
- [ ] Gate: loops 0, mid_cut 0 (by construction), translations ru/en present with untranslated 0 (failed counted separately). Read 20 random ru lines; if still word salad, Phase 4 moves ahead of Phases 2-3.
- [ ] `launchctl load ~/Library/LaunchAgents/org.tylog.transcribe.plist`.
- [ ] Commit metrics row.

## Phases 2-5 (outline; detailed plan written after the Phase 1 gate, with its numbers)

- **Phase 2, second pass:** doubtful = primary/secondary agreement ratio below a threshold set so ~10-15% of lines flag, or filter hit next to speech. Re-transcribe doubtful spans with ±3 s padding; LLM arbitration (Ornith 35b, thinking off, JSON `{text, status}`), never adds words absent from all hypotheses (script check). Gate: doubtful after pass < 5%.
- **Phase 3, context:** `== Context` section read from the note; one LLM pass -> Summary, Scenes, glossary, References (in ru, marked AI), incoherent ids; runs before Phase 2's arbitration on re-runs. App parses the new sections.
- **Phase 4, translation v2:** translation as a stage of the job; windows by scene, glossary + previous 10 pairs; review pass 1-5, retranslate < 3 once; model bake-off among Studio models on 40 clean lines. Gate: untranslated 0, failed < 2%, mean score >= 4. Then the user's Russian test recording.
- **Phase 5, app:** parallel view, marker styling, scenes/references jump lists, Re-process action; verify on the P30.
