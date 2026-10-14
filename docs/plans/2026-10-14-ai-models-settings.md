# AI and models in Settings: what exists, what a user wants, proposal

Status: analysis and proposal, nothing built. Supersedes the "AI models" idea in
`2026-10-11-model-settings-handoff.md`. Facts below come from two read-only
sweeps (app repo; the Mac's launch agents, scripts and configs) on 2026-10-14.

## 1. What exists today

The app itself never calls a chat model. Work reaches models through files in
the synced vault (`_system/jobs/*`) that scripts on the computer pick up. The
only model inside the app is the on-device embedding model.

| Task | Model today | Runs where | How it is chosen | User sees |
|---|---|---|---|---|
| Search by meaning | multilingual-e5-small (ONNX, 252 MB, fixed revision) | phone and Mac, in the app | constants | "Semantic search" sheet: download / status |
| Transcription | faster-whisper `large-v3` (script default `small`) | Mac worker, launchd every 60 s | `--model` in the plist | Settings: when + languages |
| Translation | Ornith 1.5 35b on Unsloth Studio, auto-loaded at 64k | Mac worker, calls the Studio PC | env `TYLOG_LLM_*`, else `~/.pi/agent/models.json` | Settings: when + languages |
| Screenshot text/metadata | GLM-OCR + Gemma 4 26B, metadata Qwen 3.6 27B on Studio (legacy Ollama default `qwen3.5:2b`, not installed) | Mac job written by the app (`org.tylog.screenshots*`) | constants in the script | Settings: when + time + status line |
| Article extraction | launchd forces `--provider studio` (Gemma 4 26B); `config.yaml` says Claude haiku/sonnet and is ignored | Mac worker `org.tylog.worker` | plist argument | notes carry `llm_provider` / `llm_model` |
| Explain Typst error | no model, rules only | app | none | dialog |

Settings the user can touch today: audio when/languages (synced, `_system/settings/processing.json`), screenshots mode/time (device-local `vaults.json`), semantic model download. Nothing lets the user pick a model, a server or a key.

## 2. Pain points found

- Three places hard-code the Studio host; several jobs silently depend on that PC being on.
- Two sources of truth for the article engine (`config.yaml` vs the plist argument) that disagree.
- Defaults reference models that are not installed (screenshot `qwen3.5:2b`; pi `ornith:9b`).
- Docs and plist disagree on the Whisper default (`small` vs `large-v3`).
- Screenshot OCR and backfill have no launch agent unless the app writes one; the omlx engine needs a file that does not exist.
- A job that fails because a model is missing or the server is off is invisible in the app.
- Phone and desktop have different capabilities and the UI cannot tell which task can run where.

## 3. What a regular user wants (not what the plumbing offers)

1. Outcomes, not model names: "turn my voice notes into text", "read my screenshots", "translate". A model name only matters to power users.
2. A sane default that works without choosing anything, and a one-line answer to "is it running and when did it last work?".
3. Control over privacy and cost: does this leave my machine, does it cost money. This is the first thing people ask about notes.
4. Quality vs speed as a simple knob (Fast / Balanced / Best), per task.
5. For the few who run their own server (Ollama, LM Studio, Unsloth Studio, any OpenAI-compatible URL, a cloud key): one place to add a connection, see its models, and press Test.
6. Honest limits: a phone cannot run Whisper large or a 26B model; say so and route the task to "my computer".
7. Traceability: which model produced this text (already stored as `llm_model` on article notes and `llm` on translation jobs).

## 4. Proposed structure

One Settings section "AI". Two levels, so most people never see the second.

**Level 1: task cards (everyone).** One card per task: Transcription, Translation, Screenshots, Articles, Search by meaning. A card shows status (idle / working / last result / problem), the when-choice already built (Only when I ask / Right after added / On schedule), and one knob: Quality (Fast / Balanced / Best) and Where (This device / My computer / My server / Cloud). Presets on top: **Private** (nothing leaves the machines I own), **Balanced** (my computer + my server), **Cloud** (fastest, data goes to the provider; shown with a clear notice).

**Level 2: connections and models (power users).**
- Connections: name, kind (Ollama, Unsloth Studio, LM Studio, OpenAI-compatible, cloud), URL, key; Test; the list of models it reports (`/v1/models`) with loaded state and context size.
- Per-task override: pick connection + model explicitly; Test sends one real sample (must catch a too-small context, which returns an empty reply).
- Workers: which computers are online (see below).

**Where the data lives** (the constraint that shapes everything: the app does not run chat models, workers do):
- `_system/settings/ai.json` in the synced vault, no secrets: connections (id, kind, URL, label) and per-task choices (connection id, model, quality profile, where, language list). Replaces hard-coded constants and the plist arguments; the existing `processing.json` keeps only the when/languages part or is folded in.
- Secrets never sync: keys live on the machine that uses them (worker keychain or its local config; the app keeps its own only for Test).
- `_system/workers/<host>.json`, written by each worker every minute: last seen, installed/loaded models, capabilities. The app uses it to show "Mac online" and to grey out impossible choices.
- Embeddings stay on the built-in model (changing it re-embeds the whole vault, and phones cannot reach a desktop server); show the model as read-only information.

## 5. Phases (each is a bite-sized codex task; I coordinate and verify on devices)

1. Contract + worker: `ai.json` schema and reader in the transcribe/translate worker; remove the Whisper/model constants from the plist; worker heartbeat file. Tests in Python.
2. Settings UI Level 1 cards on top of the existing policy editor; status from jobs and heartbeat.
3. Connections + discovery + Test (app side HTTP to the user's server; desktop and phone on the same network only).
4. Point article-pipeline and the screenshot job at `ai.json`; delete the disagreeing `config.yaml` / `--provider` arguments.
5. Presets and the privacy notice.
Each phase ends with a release and a check on Mac and P30.

## 6. Decisions needed

- Who is the "regular user": you plus a few friends running their own Mac worker (current reality), or people with no computer worker at all (then phone-only cloud or on-device models become the default, and phase 3 matters most)?
- Are cloud providers (API keys) in scope, or local and own-server only?
- Should the app be allowed to load/unload models on a Studio server itself (the worker already loads Ornith when it is missing), or only show them?
