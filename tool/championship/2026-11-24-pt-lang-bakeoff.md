# European Portuguese model competition (2026-11-24)

Which Studio model writes the Portuguese for phrase notes (tags `#pt`, `#pt-audio`).
Run: `tool/championship/lang_bench/run.sh`; table: `python3 tool/championship/lang_bench/bench.py --report`; raw rows: `tool/championship/lang_bench/results.jsonl`.

134 items from the pt-PT course (`tool/championship/lang_bench/data.jsonl`): 70 ru/en -> pt, 34 corrections (4 already correct),
30 pt -> ru/en. Every model loaded at 65536 context, thinking off, JSON mode, the worker's own prompts, windows of
10 lines, one model at a time with the Mac jobs stopped.

| model | to_pt sim | pt-PT forms | Brazilian | errors fixed | fix kept | ->ru | ->en | failed | bad windows | s/line | load s |
|---|---|---|---|---|---|---|---|---|---|---|---|
| ollama/ornith-1.5:35b | 0.82 | 0.77 | 2 | 0.83 | 0.93 | 0.85 | 0.85 | 0 | 1 | 0.29 | 18.8 |
| ollama/qwen3.6:27b | 0.81 | 0.81 | 4 | 0.90 | 0.97 | 0.86 | 0.90 | 0 | 0 | 2.02 | 20.0 |
| Qwen3.6-35B-A3B-UD-Q4_K_M | load failed: not loaded after 15 min |
| unsloth/Qwen3.8-27B-GGUF | 0.85 | 0.86 | 3 | 0.93 | 0.98 | 0.91 | 0.83 | 0 | 0 | 4.11 | 222.8 |
| unsloth/gemma-4-26B-A4B-it-qat-GGUF | 0.85 | 0.83 | 1 | 0.97 | 0.98 | 0.85 | 0.83 | 0 | 0 | 0.15 | 12.1 |
| unsloth/LFM2.5-24B-A2B-GGUF | 0.82 | 0.81 | 4 | 0.79 | 0.90 | 0.83 | 0.81 | 5 | 6 | 7.87 | 175.4 |
| unsloth/Muse-Glimmer-30B-GGUF | 0.86 | 0.82 | 0 | 1.00 | 0.99 | 0.88 | 0.85 | 0 | 0 | 7.81 | 199.6 |
| unsloth/Inkling-2-Mini-GGUF | 0.83 | 0.74 | 1 | 0.93 | 0.97 | 0.87 | 0.80 | 0 | 0 | 1.99 | 220.2 |
| unsloth/flint-GGUF | 0.79 | 0.80 | 3 | 1.00 | 0.98 | 0.86 | 0.81 | 20 | 8 | 21.73 | 293.0 |
| prism-ml/Ternary-Bonsai-2-27B-gguf | 0.79 | 0.70 | 7 | 0.83 | 0.95 | 0.86 | 0.81 | 0 | 0 | 0.35 | 107.6 |

Columns: `to_pt sim` = word similarity to the course line; `pt-PT forms` = share of expected European forms present;
`Brazilian` = Brazilian forms found in all outputs; `errors fixed` = share of planted errors corrected; `fix kept` =
similarity to the correct line (over-editing lowers it); `failed` = lines with no usable answer.

## Reading 20 outputs (12 to_pt, 8 fix; gemma-4, Muse-Glimmer, Qwen3.8, Ornith side by side)

- Ornith made two real mistakes the scores under-weight: "no casa de banho" (wrong gender) and it copied the
  hint "(a um amigo)" into the output and wrote "remate" for "goal".
- Ornith and Muse-Glimmer changed the correct "a casa do Rui" to "à casa do Rui"; gemma-4 and Qwen3.8 left it.
- Muse-Glimmer alone produced the idiomatic "Apetece-me café"; the others wrote "Tenho vontade de".
- gemma-4 had no mistake in the 20. Qwen3.8 over-edited once ("Vou para a escola").

## Decision

Champion for the `phrases` task: `unsloth/Muse-Glimmer-30B-GGUF` (user decision: no Brazilian forms at all). It is
the only model with zero Brazilian forms in 134 lines and it fixed every planted error. gemma-4 was the fast
runner-up but kept the Brazilian "tela" in a correction.

Found after the run: Muse-Glimmer reasons before every answer even with thinking switched off (the reply carries
`reasoning_content`). So it was the only model that could think, which explains both its 8 s/line and part of its
lead; the comparison with the others was not on equal terms. Consequences in the worker: phrase jobs ask with an
8000-token reply limit and do their own language check (the worker's 16-token one comes back empty).

Because the model is slow and takes 200 s to load, phrase jobs run once a day from the processing time (03:00),
not on the fly. Every Portuguese line is also checked against the Brazilian list (`phrase_notes.BRAZILIAN`); a hit
is asked again once and, if it stays, flagged in the note.

Ornith (current `translate` model) is behind gemma-4 on every Portuguese score and no faster. Moving the
`translate` task to gemma-4 is an option, not done here: this bench does not cover the long audio-note texts.

Not measured: naturalness judged by a Portuguese speaker; texts longer than one line.

## Speech heat

`tool/championship/lang_bench/tts_heat.py`, six course lines per engine, no language model loaded, Mac jobs stopped.
Score = word accuracy of the Studio transcript against the text. Raw rows: `tool/championship/lang_bench/tts_results.jsonl`.

| engine | clips | score | s/clip | load s | course voice |
|---|---|---|---|---|---|
| Chatterbox-GGUF (GPU) | 6/6 | 0.94 | 1.7 | 8 | yes |
| Chatterbox-GGUF (CPU) | 6/6 | 0.94 | 46.9 | 8 | yes |
| orpheus-3b-0.1-ft | 6/6 | 0.73 | 14.7 | 97 | no |
| MOSS-TTS-Local-Transformer-v1.5 | load failed: not enough free GPU memory | | | | |
| Qwen3-TTS-12Hz-1.7B-CustomVoice | 0/6: loads, then speech answers "No model loaded" | | | | |

Decision: Chatterbox stays, on the GPU (unload the language model for the audio batch). CPU works with the same
score but is 27 times slower; usable only for a handful of clips without unloading the language model.
