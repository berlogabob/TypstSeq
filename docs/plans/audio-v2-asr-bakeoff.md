# Audio v2 ASR bake-off on Studio (Task 3)

Run 2026-10-31 on `http://desktop-vdsrh2e:8888` with `tool/asr_bakeoff.py`. 8 clips cut from the source recording (4 speech, 3 music at 30 s, 1 short at 5 s), `language=pt`. Every load and run used `device=cpu`: the RTX 5080 holds `ollama/ornith-1.5:35b` (13.1-13.8 of 15.9 GB) and was not touched, so the s-per-30-s column is CPU time.

## Client contract

Auth: `Authorization: Bearer <key>`, key from `~/.pi/agent/models.json` `providers.studio.apiKey`.

- Text, all four engines: `POST /api/inference/audio/transcribe`, JSON `{"audio": base64(WAV 16 kHz mono), "engine": E, "model": M, "language": "pt", "device": "cpu"}` returns 200 `{"text","language","duration","model"}`. Tested pairs: (transformers, `large-v3-turbo`), (transformers, `large-v3`), (mtmd, `qwen3-asr-1.7b`), (audiocpp, `audio-cpp/audio.cpp-gguf/Parakeet-TDT-0.6B-v3-GGUF`).
- Load: `POST /api/inference/audio/stt/load` `{"engine","model","device":"cpu"}`, returns once resident (2-6 s). Unload: `POST /api/inference/audio/stt/unload?engine=E&model=M&wait=true`.
- Download: `POST /api/inference/audio/stt/download` `{"engine","model"}`, then poll `stt/status`, field `[E].download.downloading`. Each model finished in under 1 min; nothing hit the 20 min cap.
- Word timings: `POST /v1/audio/transcriptions` multipart with `file`, `model`=M, `language=pt`, `response_format=verbose_json`, `timestamp_granularities[]=word`, returns `words: [{word,start,end}]`. Parakeet only. Transformers and mtmd return 400 "timestamp_granularities is not supported by the local STT engine".
- Parakeet's /v1 text differs from its JSON text on the same clip (`v1_matches_json=False`). Keep one path per transcript.

## Table

| engine | arch | status | load s | music garbage (of 3) | music words | credit hits (of 8) | speech agreement | s per 30 s | word timestamps |
|---|---|---|---|---|---|---|---|---|---|
| whisper-large-v3-turbo | whisper | ok | 5.5 | 2 | 133 | 0 | 0.629 | 8.3 | no |
| whisper-large-v3 | whisper | ok | 6.0 | 2 | 345 | 0 | 0.559 | 72.3 | no |
| qwen3-asr-1.7b | qwen3-asr | ok | 2.2 | 2 | 1385 | 0 | 0.617 | 14.6 | no |
| parakeet-tdt-0.6b-v3 | parakeet | ok | 1.6 | 0 | 0 | 0 | 0.485 | 5.8 | yes |

Garbage = loop (over 20 words, unique/total < 0.25), credit line, or failed call. Empty output is not garbage. Agreement = mean `SequenceMatcher` ratio on lowercased words, over the 4 speech clips and the other engines.

## Decision (plan rule)

- Primary: parakeet-tdt-0.6b-v3 (0/3 music garbage, the only engine with word timings). Its speech agreement is the lowest (0.485).
- Secondary: whisper-large-v3-turbo (2/3 garbage, agreement 0.629), the best Whisper-family engine.
- The turbo primary / qwen3 secondary decision only follows if empty music output counts as garbage (parakeet 3/3). That contradicts Review Focus 1 (music-only gives `[—]` lines), so it is not adopted here. Needs a call before Task 7.

## Reviewer notes (read by eye)

Read by eye: qwen3-asr is best on the cultural clip 23:00 (Deméter, Perséfone, submundo) but drops punctuation on 06:00; whisper-large-v3 is best on 06:00 (aristocratas, Barreiro) but 72 s per 30 s clip, likely not on GPU, too slow for the 60 min budget; parakeet returns nothing on music clips (candidate music gate for Phase 2 if loops remain) and is weakest on speech.

Fact behind "likely not on GPU": every run used `device=cpu`, so the 72 s is a CPU figure.
