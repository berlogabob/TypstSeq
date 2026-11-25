#!/usr/bin/env python3
"""Which Studio speech engine reads European Portuguese best.

    python3 tool/championship/lang_bench/tts_heat.py <out dir> [engine[@cpu] ...]     # appends to tts_results.jsonl

Each engine speaks the six lines below with the course voice (saved voice "tugao1") when it accepts one,
else with its own default voice. Score = word accuracy of the Studio transcript against the text
(phrase_audio.accuracy). Accent is not measured: listen to the clips in <out dir>.
"@cpu" loads the engine on the CPU, which leaves the GPU to the language model.
"""
import json, sys, time
from pathlib import Path
from urllib.error import HTTPError

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parents[1]))
import phrase_audio  # noqa: E402

ENGINES = ["audio-cpp/audio.cpp-gguf/Chatterbox-GGUF", "audio-cpp/audio.cpp-gguf/Chatterbox-GGUF@cpu",
           "OpenMOSS-Team/MOSS-TTS-Local-Transformer-v1.5", "Qwen/Qwen3-TTS-12Hz-1.7B-CustomVoice",
           "unsloth/orpheus-3b-0.1-ft"]
LINES = ["Boa tarde. Sinto-me mal desde ontem. Dói-me a cabeça e doem-me as costas.",
         "Tome estes comprimidos, um de oito em oito horas, e beba muita água.",
         "A que horas parte o próximo comboio para Sintra?",
         "Desculpa, não percebi. Fala mais devagar, por favor.",
         "Quis apanhar o metro, mas não consegui, por isso cheguei a casa tarde.",
         "Queria marcar uma consulta com o médico de família."]


def error_text(error):
    return f"{error.code}: {error.read()[:200].decode('utf-8', 'replace')}" if isinstance(error, HTTPError) else str(error)[:200]


def run(engine, out):
    model, _, device = engine.partition("@")
    row = {"engine": engine, "clips": []}
    started = time.monotonic()
    try:
        phrase_audio.studio("/v1/load", {"model_path": model, **({"audio_device": device} if device else {})}, seconds=900)
    except (HTTPError, OSError) as error:
        return {**row, "load_error": error_text(error)}
    row["load_s"] = round(time.monotonic() - started, 1)
    voices = {voice["name"]: voice["id"] for voice in json.loads(phrase_audio.studio("/v1/audio/voices"))["voices"]}
    for index, line in enumerate(LINES):
        clip = {"line": index}
        for voice in (voices.get("tugao1"), None):  # an engine without cloning refuses the saved voice
            started = time.monotonic()
            try:
                mp3 = phrase_audio.speak(line, voice)
            except (HTTPError, OSError) as error:
                clip["error"] = error_text(error)
                continue
            clip.pop("error", None)
            clip.update(sec=round(time.monotonic() - started, 1), cloned=voice is not None,
                        score=round(phrase_audio.accuracy(line, phrase_audio.transcribe(mp3)), 2))
            (out / f"{engine.replace('/', '_')}-{index}.mp3").write_bytes(mp3)
            break
        row["clips"].append(clip)
        print(engine, clip, flush=True)
    return row


if __name__ == "__main__":
    out = Path(sys.argv[1])
    out.mkdir(parents=True, exist_ok=True)
    with (HERE / "tts_results.jsonl").open("a", encoding="utf-8") as stream:
        for engine in sys.argv[2:] or ENGINES:
            stream.write(json.dumps(run(engine, out), ensure_ascii=False) + "\n")
            stream.flush()
