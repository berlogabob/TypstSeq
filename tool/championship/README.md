# Model championship

Which local model on the Unsloth Studio PC does each TyLog job best. Rerun when new models appear:

    tool/championship/run.sh <model id> [<model id> ...]

It stops the Mac jobs that use the Studio, runs each model through the three competitions at 65536 context,
prints the three tables and starts the jobs again. Old rows are kept, so new models are compared with the
earlier ones without rerunning them. Takes 1 to 3 hours per model.

| Competition | Folder | Decides | Champion (2026-11-25) |
|---|---|---|---|
| Coding | `model_bench/` | the delegate for code work (`pi-run.sh`) | `ollama/ornith-1.5:35b` |
| European Portuguese | `lang_bench/` | `phrases` task | `unsloth/Muse-Glimmer-30B-GGUF` |
| Mention extraction | `extract_bench/` | `enrich` task | `ollama/ornith-1.5:35b` |
| Speech | `lang_bench/tts_heat.py` | phrase audio | Chatterbox-GGUF on the GPU |

Rules:
- Nothing else on the Studio during a run (the script stops the jobs; do not start other work there).
- Time: a model slower on the first coding task than the first two candidates (166 s) is stopped
  (`model_bench/skip_slow.sh`).
- Portuguese: European only. Any Brazilian form counts against a model.
- Journal text is private: extraction inputs and rows live in `~/Documents/tylog-gold/extract-bench/`.

Write-ups: `2026-11-24-pt-lang-bakeoff.md` (Portuguese, speech), `2026-11-25-extract-bakeoff.md` (extraction),
`model_bench/README.md` (coding). Older single-purpose scripts in `model_bench/` (`run_all.sh`, `run_ctx64.sh`,
`run_compare35.sh`, `run_new_models.sh`) are kept as they were run.
