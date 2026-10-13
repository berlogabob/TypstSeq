# Handoff 2026-10-11: local models and "bring your own model" settings

State at the end of the session, so work can resume after a reboot.

## Done
- 0.12.4+137 released and on the P30. A24 is one build behind (it has a local
  0.12.4 from before the last four P30 fixes); it updates from the published APK.
- Coding-delegate bench: `tool/model_bench/` (README, `report.txt`, PDF in
  `report/`). Default delegate is `ollama/ornith-1.5:35b` on Unsloth Studio
  through `pi-run.sh`.
- 35B Q4 against the friend's `pfeifferj/...GSQ-RCO` 3.5-bit build: equal on
  four tasks; on the bug fix 2/3 against 1/3 at 64k, both 0/3 at 32k. See the
  README section "Context window matters".

## Not committed / not pushed
- Local commit `32cad46` (32k comparison) is not pushed.
- Uncommitted: 64k rows in `results.jsonl`, `report.txt`, `run_ctx64.sh`, the
  README section, this file.
- The PDF report covers the first four models only, not the 32k/64k rounds.

## Next: which model for the app's own jobs
The app never calls a chat model. Models are used by two desktop producers and
by on-device search:

| Job | Runs in | Model today |
|---|---|---|
| Article extraction and preparation | `~/Nextcloud/scripts/article-pipeline` | `config.yaml`: Claude haiku, fallback sonnet. Studio override in `engine.py`: Gemma 4 26B, fallback Qwen 3.6 27B |
| Screenshots | macOS background job set up by `lib/screenshots_ocr.dart` | not verified; needs a vision model |
| Semantic search | in the app, `lib/retrieval/` | built-in `multilingual-e5-small` ONNX, 235 MB |
| Clustering | in the app, `lib/graph.dart` | not verified whether it uses embeddings or only tags and links |
| Tag synonym proposals | pipeline script `propose_tag_synonyms.py` | an embedding model |

Open question from the user: is Ornith 1.5 9b enough for extraction? Not
measured. The coding bench says nothing about it, and whether Ornith reads
images is unverified.

Steps, in order:
1. Read the two unverified rows (screenshot job's model, clustering input).
2. Extraction bench, same shape as the coding one: about 20 saved articles,
   each model 3 runs, scored on valid output, tags taken from the existing
   vocabulary, and whether the rendered Typst compiles. Candidates: Ornith 9b,
   Ornith 35b, the friend's 3.5-bit build, Gemma 4 26B as the current baseline.
3. Settings design (proposal, not approved): one desktop "AI models" screen.
   - Server: OpenAI-compatible URL and optional key (covers Ollama, Unsloth
     Studio, LM Studio, cloud).
   - Text model and vision model, picked from the server's `/v1/models`, each
     with a Test button that sends one real sample and checks the reply parses.
     The test must catch a too-small context window (empty reply).
   - Embeddings stay on the built-in model: changing it means re-embedding the
     whole vault, and the phone cannot reach a desktop server.
   - The app writes the pipeline's existing `config.yaml` (provider, base URL,
     primary and fallback model), as it already configures the screenshot job.
4. Setup note for a third person: load the model at 64k context or more.

## Still open from earlier
- Never checked on a phone: Ctrl+Enter on a hardware keyboard, conflict
  resolution, image blocks, "Index rebuilt" pill, "Continue reading" inside
  Agenda, the ~55 s wait before lists fill on the A24.
- P30 pickup of the clean server copy of the 2026-10-08 page not confirmed.
- Parked: audit findings C10/C12/C13/C16; design decisions (8dp corners,
  merged confirm dialogs, 48dp calendar cells); Ornith 27b coder failing at
  1/15 (probably the 8k-context fault, unconfirmed); `pi-delegate` SKILL.md
  header and pi's `settings.json` still name ornith:9b.
