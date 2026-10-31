# Audio notes v2: one document per recording, faithful transcript, contextual translation

Date: 2026-10-31. Status: design, awaiting approval. Branch: `feat/audio-notes-module-packs`.

## Why

The first long real recording (theatre "Uma Mosca no Nosso Chá", Formiga Atómica,
1h44, European Portuguese, `notes/Audio Friday at 21-17.typ`) produced a transcript
and a Russian translation that read as a bag of words. The user wants the whole
path fixed as a system: recording -> transcript -> translation -> understanding
(summary, scenes, cultural references) -> own comments, in one document.

Theatre text is dense with cultural references (Demeter and Baubo, the agelast
stone, Aristophanes, Girondins and Jacobins, St Lawrence as patron of comedians);
even a Portuguese speaker misses them. The user is also learning European
Portuguese (the pt-pt A2/B1 pack), so the original text must be faithful, not
paraphrased.

## Measured baseline (this recording, current pipeline)

| Metric | Value |
|---|---|
| Lines (fixed 30 s chunks) | 205 |
| Lines that are hallucination loops ("É isso aí!" x100, "Não, não, ..." , "A CIDADE NO BRASIL") | 40 (20%) |
| Lines ending mid-sentence (chunk cut through speech) | 51 (25%) |
| Translation lines with no Cyrillic (left in Portuguese) | 66 (32%) |
| Known Whisper credit hallucination ("Legenda por Sônia Ruberti") | present |
| Transcription time / translation time | 3 min (Studio) / 37 min (Studio LLM) |

Errors visible by reading: names and terms misheard (Deméria for Deméter, Paulo for
Baubo, "pedra arjolasta" for pedra agelasta, "Jirondinos/Jacobinos" garbled), Brazilian
forms inserted into European Portuguese speech ("Estou ouvindo", "É isso aí").

## Root causes (verified, not guessed)

1. **Fixed 30 s chunks, no voice activity detection.** Music, songs, laughter and
   applause go to Whisper as if they were speech; Whisper fills them with loops and
   training-data credits. Cuts fall inside sentences.
2. **No context reaches Whisper.** Probe 2026-10-31: the Studio endpoint
   (`/v1/audio/transcriptions`, `unsloth/whisper-large-v3-turbo`) returns identical
   text with an empty prompt, with the exact correct sentence as prompt, and with an
   unrelated prompt. It ignores `prompt`, returns no segments, no confidences, and
   rejects `timestamp_granularities` ("Use a saved STT connection with provider_id
   for word or segment timings"). Each chunk is decoded blind: no previous text, no
   names, no hint that this is European Portuguese.
3. **No confidence signal anywhere.** Nothing tells the pipeline which places are
   doubtful, so nothing can get a second look.
4. **Translation input is garbage-shaped.** The unit of translation is a 30 s blob
   cut mid-sentence, ten blobs per request, with no knowledge of the play, its names,
   or what came before. A 35B local model cannot fix that; it translates fragments
   into fragments. Failed lines silently keep the Portuguese text.

Conclusion: a second pass alone would polish garbage. The order is: clean input,
units that are sentences, context at every step, then a second pass where it is
still doubtful.

## Goals

- Transcript lines are sentences or short utterance groups, with timestamps,
  faithful to what was said, European Portuguese spelling.
- Music, laughter, applause are marked as such, never transcribed as words.
- Doubtful places are found automatically, get a second pass, and anything still
  doubtful is visibly marked, not silently guessed.
- Translation is made with context: what the piece is, names glossary, the
  surrounding lines. Failed lines are marked, not left in the source language.
- One document per recording: summary, scenes, references, parallel text, comments.
- The user's own edits are never overwritten by a re-run.
- Quality is measured on this recording before and after each phase.

## Non-goals

- Live / streaming transcription.
- Automatic naming of speakers (labels like "A", "B" are allowed later; names no).
- Web lookup for references (the user can paste programme text instead).
- TTS, dubbing, audio packs (user parked audio generation).
- On-device ASR on phones.

## Anti-goals (failure even if it "works")

- The LLM rewrites speech into fluent text nobody said. Correction may only choose
  between what was heard or fix a word to a known name/term; otherwise mark `(?)`.
- A re-run overwrites a line the user corrected.
- Reference explanations presented as fact without a marker that they are AI-made.
- The pipeline takes hours or loads big models on the Mac by default (24 GB M4 Pro,
  oMLX history).

## The document (one note per recording)

Kept compatible with the current app contract (`lib/audio/audio_note_doc.dart`):
sections are `== Heading`, timed lines are `- mm:ss text`, the app parses
`== Transcript` and `== Translation <lang>` and seeks on tap.

```
= <title>
#tylog.attachment("/assets/<file>", kind: "audio")[...]

== Context        user-written: programme text, cast, synopsis, anything; fed to every prompt
== Summary        5-10 sentences, generated
== Scenes         - 06:00 Monologue: family of comedians (generated)
== References     - 23:00 Baubo -- in the Demeter myth, ... (generated, marked AI)
== Comments       user's timed comments (unchanged)
== Transcript     - 06:00 Nasci no seio de uma família muito respeitada.
                  - 06:04 (?) Eram-nos praticamente... aristocratas.
                  - 07:12 [música]
== Translation ru - 06:00 Я родилась в очень уважаемой семье.
```

Transcript and translation lines are aligned 1:1 by position (same count, same
timestamps; see Edit protection for ties), so the app can show them in parallel (original over translation) without a new format.
Markers: `(?)` = still doubtful after the second pass; `[música]`, `[risos]`,
`[aplausos]` = non-speech; `[sem tradução]` = translation failed. Exact marker
glyphs are the builder's call as long as they survive `escapeMarkup` and Typst
compiles.

## Pipeline

Run order: 1, 2, 3, 5, 4, 6, 7. The context pass (5) runs before the second pass
(4) so the glossary exists when doubtful lines are arbitrated. Translation is a
stage of the same job, not a separate job enqueued when a Transcript appears.

Each stage writes its result into a sidecar `_system/jobs/segments/<hash>.json`
(the job hash already exists; a separate directory so the worker's job scan never
reads it as a job) and records the stage as done, so a restarted worker resumes,
and a later stage can be re-run alone. The sidecar syncs (resume on another
machine, Re-process from the phone); it is written once per stage, not per line.
The note is rendered from the sidecar plus the user's edits at each stage
boundary, read-modify-write right before writing, never from a copy taken at claim
time, so partial results are visible and edits made mid-run survive.

Sidecar per line: `id, start_ms, end_ms, kind (speech|music|laughter|applause),
asr (first hypothesis), asr_alt (second pass, if any), text (final), flags,
status (ok|fixed|doubtful), translations {lang: {text, score}}, rendered {section: text}`.
`rendered` is what the worker last wrote into the note; see Edit protection.

### Stage 1. Audio preparation and speech map
- ffmpeg: mono 16 kHz, high-pass ~80 Hz, loudness normalisation.
- Voice activity detection (Silero VAD, ONNX, runs on the Mac CPU in seconds for
  2 h) gives speech regions. Gaps become `[música]` / `[risos]` / `[aplausos]` lines
  only when long (> ~5 s); short gaps are just pauses. Classifying the non-speech
  kind is optional; plain `[—]` with duration is acceptable for v1 (builder's call).
- Speech regions are merged into ASR chunks of at most ~25 s, cut at the longest
  pause, never inside speech.

### Stage 2. First transcription, with context
Studio engines take no prompt (see "Where it runs"); this stage is two independent
engines on the same chunks, picked in Phase 0.
- Language as today (job `lang`, else detected).
- Hallucination filter per segment: compression ratio > 2.4, n-gram loop detector
  (current `collapse_repeats` logic generalised), no-speech probability high with
  low log-probability, and a blocklist of known credit phrases ("Legenda por",
  "Legendas pela comunidade", "Subtitles by", lone "Obrigado." at chunk end). A hit
  becomes a non-speech line, not text.
- Resegmentation: words (with timestamps) are regrouped into sentences by
  punctuation; very short sentences (< 3 words) join their neighbour; a line never
  exceeds ~20 s. Each line gets the timestamp of its first word.

### Stage 3. Doubtful-place detection
Required from the runtime: segment `avg_logprob`, `no_speech_prob`,
`compression_ratio`. Word probabilities are used when the runtime gives them
(in-process faster-whisper and mlx-whisper do; OpenAI-style HTTP `verbose_json`
does not).
A line is doubtful if any holds: segment log-probability below a threshold, a run
of low-probability words (when available), filter hit adjacent to speech, a word not in a European
Portuguese word list that is also not in the glossary, or the context pass
(Stage 5) flags it as incoherent. Thresholds are set in Phase 0 on this recording
so that roughly the worst 10-15% of lines are flagged; builder's call within that.

### Stage 4. Second pass on doubtful places
For each doubtful line:
1. Re-transcribe the span with ±3 s padding (a cut no longer falls at the chunk
   edge), with the primary engine and, if the bake-off found one worth it, a third.
2. LLM arbitration: input = all hypotheses, 3 lines before and after,
   glossary, Context. Output JSON `{text, status: ok|fixed|doubtful, note}`.
   Rules in the prompt: choose between hypotheses or correct a word to a glossary
   entry or an obvious European Portuguese word; never add content; when unsure
   return the better hypothesis with status `doubtful`.
3. Lines that stay `doubtful` get `(?)` in the note.

### Stage 5. Context pass over the whole text
One LLM call over the cleaned transcript (1h44 is ~15k words, ~25k tokens; fits the
64k context of the Studio models) plus the user's Context section. Output JSON:
summary, scenes `{start_ms, title}`, glossary `{term, kind, canonical spelling,
ru rendering}`, references `{start_ms, term, explanation_ru, confidence}`,
incoherent line ids (added to the doubtful set before Stage 4).
Glossary is saved in the sidecar and reused by Stages 2, 4 and 6 on re-runs.

### Stage 6. Translation with context
- Unit = transcript line (sentence). Window = one scene, or ~40 lines if no scenes.
- Prompt = Summary + glossary with fixed ru renderings + the previous 10 source and
  translated lines + the window as `{id: text}`. Reply JSON `{id: translation}`.
- Validation per line: id present, target script present (Cyrillic for ru), length
  ratio within ~0.3-3. A failing line is retried once alone with the window as
  context; still failing -> `[sem tradução]`, never the source text.
- Non-speech lines are not sent; their markers are copied.

### Stage 7. Translation review (second pass for translation)
Per window, a separate call rates each line 1-5 for faithfulness and readability
with a one-phrase reason. Lines rated below 3 are retranslated once with a wider
window and thinking enabled (or the stronger model from the Phase 0 bake-off).
The score is stored in the sidecar; lines that stay below 3 are marked `(?)` in the
translation.

### Edit protection
Matching: note lines are matched to sidecar lines in section order by
`(mm:ss, rendered text)`; equal timestamps are resolved by order (the Dart parser
gets a stable sort with the line index as tie-break, so two sentences starting in
the same second keep their order and pair 1:1 with the translation).
- Note line equals `rendered`: untouched, the worker may rewrite it.
- Note line differs: edited by the user. It is kept with its time span pinned
  (its start to the next line's start); on a re-run, new ASR lines inside that span
  are dropped. Its text becomes ground truth: sidecar `text`, status `user`,
  context for neighbours, names can enter the glossary. Its translation line is
  re-translated unless the translation line itself was edited.
- `rendered` line absent from the note: deleted by the user, stays deleted.
- Legacy notes (no sidecar): never auto-reprocessed. Re-process on one replaces
  Transcript and Translation wholesale after saving the old note text next to the
  sidecar (`<hash>.v1.typ`); Comments and Context are kept.
The same rules apply to Summary, Scenes and References (per line). Context and
Comments are never written by the worker.

## Where it runs

Heavy work on the Studio PC (`http://desktop-vdsrh2e:8888/v1`), Mac only as
fallback (user rule). Facts:

- Studio's built-in STT ignores prompts and returns no timings or confidences. It
  can stay as a "fast draft" engine, but Stages 2-4 need a different runtime.
- Unsloth Studio says word/segment timings need "a saved STT connection with
  provider_id": it can proxy to an external OpenAI-compatible STT server.

- Studio has more STT engines than the one in use (probe 2026-10-31,
  `/api/inference/audio/stt/status`): Whisper tiny..large-v3 (transformers and
  gguf), Qwen3-ASR 0.6B/1.7B (mtmd, audio.cpp), Parakeet-TDT-0.6B-v3, Canary-180M,
  Nemotron ASR (audio.cpp). Only large-v3-turbo is downloaded. No engine takes a
  prompt. `/api/inference/audio/transcribe/source` accepts `timestamps: true`
  (segment and word timings) on engines that support it; transformers Whisper
  reports `timestamps: unsupported`.

Decision (user, 2026-10-31): Studio only for heavy work, through the Unsloth API
with the key pi stores (`~/.pi/agent/models.json` providers.studio.apiKey). The Mac
is a fallback and must never be overloaded: it has frozen and shut down under load.
Mac fallback = the existing faster-whisper CPU path under a guard: refuse to start
when free memory is low, `nice`, one job at a time, no model larger than `small`.
No mlx or other GPU models on the Mac.

Consequences for the pipeline, since Studio ASR takes no prompt:
- Context priming of ASR (Stage 2 prompt) is dropped; context enters at the LLM
  stages (4-7) instead.
- Doubtful-place detection (Stage 3) is driven by disagreement between two
  independent engines run on the same chunk (for example Whisper large-v3 and
  Parakeet-TDT or Qwen3-ASR), plus the hallucination filter and the LLM incoherence
  flags. Confidence fields are used only if an engine returns them.
- Word timings come from the engine that has them; otherwise line times are the
  chunk start plus a character-proportional offset (seconds resolution is enough).
- Phase 0 picks the primary and secondary engines by a bake-off on this recording.

LLM stages use the Studio LLM endpoint as today (thinking off by default, JSON
replies). Phase 0 picks the translation model by a bake-off among the installed
Studio models (`ollama/ornith-1.5:35b`, `ollama/qwen3.6:27b`, `ollama/gemma4:26b`,
`unsloth/gemma-4-26B-A4B-it-qat-GGUF`) on 40 lines from this recording.

Worker robustness (found today: the worker hung 27 min at 0% CPU inside one Studio
request, `urlopen` timeout did not fire): every HTTP call gets a hard wall-clock
deadline independent of the socket timeout; a stuck stage is abandoned and retried
from the sidecar. The `org.tylog.transcribe` agent is currently unloaded and is
reloaded once this fix lands.

Time budget for a 1h44 recording, end to end: under ~60 min, unattended.

## App changes

- Audio note screen: parallel mode (original line, translation under it, same tap
  to seek), markers styled (doubtful dim/underlined, non-speech as a chip),
  Scenes as a jump list, References as tappable entries that seek.
- No new file format: everything is parsed from the sections above.
- Editing a transcript line in the normal editor is the correction path; nothing
  else is needed for edit protection on the app side.
- "Re-process" action on the note re-queues the job (keeps user edits).

## Phases and acceptance

Every phase re-runs this recording and reports the metric table. Lessons from the
pt-pt pack (clean studio speech) are a regression check: they must not get worse.

0. **Baseline and probes.** Metrics script (loops, mid-sentence cuts, non-speech
   marked, doubtful rate, untranslated, translation score distribution). User
   corrects one 3-minute gold span (06:00-09:00) once -> word error rate
   before/after. Translation model bake-off. ASR runtime decision and setup. Worker
   hard-deadline fix, agent reloaded.
1. **Clean transcript.** Stages 1-2 + resegmentation + sidecar + edit protection.
   Target: 0 loop lines in text, 0 mid-sentence cuts, WER on gold span clearly
   down (target set after Phase 0 measures it).
2. **Second pass.** Stages 3-4. Target: doubtful rate after second pass < 5% of
   lines; no line where the second pass added words absent from both hypotheses
   (checked by script).
3. **Context.** Stage 5 + Summary/Scenes/References/Context sections. Target: user
   reads Summary and References for this play and judges them useful; every
   reference explanation marked AI.
4. **Translation v2.** Stages 6-7. Target: 0 lines left in source language;
   `[sem tradução]` < 2%; mean review score >= 4; user spot-check of 30 random
   lines.
5. **App.** Parallel view, markers, scenes/references navigation, re-process.
   Verified on the P30 with the real vault.

## Calls made in this design (Claude's, not the user's; check them)

- First run never waits for Context: it runs with whatever Context exists. Re-process
  re-runs from Stage 2 (ASR is minutes) and keeps user edits; that is how a
  pasted programme improves names.
- Summary, Scenes and References are written in the translation target language
  (the first in `translate_to`, ru for this user); field names are per language,
  not `_ru`.
- v2 replaces v1 for every new recording, any language. Language autodetect, mixed
  `langs` and speaker labels stay. The priming sentence and word list come from a
  dialect setting in `ai.json` (`pt` -> `pt-PT` for this user); no dialect setting
  means no priming.
- The 60-minute budget is a target, not a gate. Over budget, first Stage 7
  retranslation runs with thinking off, then Stage 4 is limited to the worst lines.
- Baseline: the current note text is copied once to the sidecar folder before the
  first v2 run, so before/after metrics use the same input.
- Without the gold span, Phase 1 acceptance uses proxy metrics only (loops, cuts,
  doubtful rate, review scores).
- Cloud: no new plumbing; the existing per-task connection in `ai.json` is the
  switch. Tuning uses local models only.

## Left to the builder

Exact thresholds (within the stated targets), marker glyphs, non-speech
classification method, prompt wording, window sizes, sidecar field names, how the
metrics script is invoked, whether Stage 5's incoherence loop runs once or not at
all if Stage 3 already catches enough.

## User answers (2026-10-31)

1. Runtime: Studio via the Unsloth API; Mac only as guarded fallback (see Where it
   runs).
2. Cloud models must exist as an option per task, but all tuning now is done with
   local models only (local is the hard case; cloud models do not make these
   errors). The option reuses the existing `ai.json` task connection
   (`tasks.<task>.connection`); every LLM stage must honour it.
3. No gold span from the user: the user does not understand the theatre original.
   Acceptance on this recording uses proxy metrics. A later user test: a Russian
   recording on a topic the user knows well, to judge transcript and translations.
4. **Critical: every recording ends with its text in three languages, ru, en and
   pt.** The source language is the Transcript; the other two are Translation
   sections. A recording in a fourth language gets all three translations. This is
   an invariant of the job, not a setting that can turn it off (extra languages
   from `translate_to` are added on top).
