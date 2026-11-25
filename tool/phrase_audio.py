"""Portuguese audio for phrase notes, made and checked on the Studio PC.

speak() is Studio text-to-speech; transcribe() + accuracy() check a clip against its text without a
Portuguese ear (same method as tylog-pack-pt-pt tools/check_audio.py).
"""
import array
import difflib
import hashlib
import io
import json
import re
import shutil
import subprocess
import tempfile
import unicodedata
import wave
from pathlib import Path
from urllib.request import Request, urlopen

import transcribe_worker as worker

STT_MODEL = "large-v3-turbo"
TTS_MODEL = "audio-cpp/audio.cpp-gguf/Chatterbox-GGUF"  # won the speech heat, tool/championship/2026-11-24-pt-lang-bakeoff.md
VOICES = ("tugao1", "tugao2")  # saved on the Studio; the course voices
PASS = 0.9  # a clip whose transcript matches its text less than this is made again, up to 4 times; the best is kept
SPEAKER = re.compile(r"^([^\W\d_][\w .-]{0,20}):\s+(\S.*)$")
FFMPEG = shutil.which("ffmpeg") or "/opt/homebrew/bin/ffmpeg"  # launchd PATH is minimal
NUMBERS = set("""zero um uma dois duas tres quatro cinco seis sete oito nove dez onze doze treze catorze
quatorze quinze dezasseis dezassete dezoito dezanove vinte trinta quarenta cinquenta sessenta setenta
oitenta noventa cem cento duzentos trezentos quatrocentos quinhentos seiscentos setecentos oitocentos
novecentos mil e""".split())
SAME = {"sr": "senhor", "sra": "senhora", "registro": "registo", "aluguel": "aluguer"}


def studio(path, body=None, *, data=None, content_type="application/json", seconds=300):
    """Response bytes of a Studio call. `path` starts with /v1/ or /api/; `body` is sent as JSON, `data` as is."""
    base, key = worker.connection_credentials()
    root = base.rstrip("/").rsplit("/v1", 1)[0]
    if body is not None:
        data = json.dumps(body).encode("utf-8")
    request = Request(root + path, data=data, headers={"Authorization": f"Bearer {key}", "Content-Type": content_type})
    with urlopen(request, timeout=seconds) as response:
        return response.read()


def speak(text, voice=None, model=None, response_format="mp3"):
    """Audio bytes of `text` in Portuguese; `voice` is a saved voice id, `model` a text-to-speech model id."""
    body = {"input": text, "response_format": response_format, "language": "pt"}
    if voice:
        body["voice"] = voice
    if model:
        body["model"] = model
    return studio("/v1/audio/speech", body)


def transcribe(mp3):
    return json.loads(studio(f"/api/inference/audio/transcribe/raw?language=pt&model={STT_MODEL}",
                             data=mp3, content_type="audio/mpeg"))["text"]


def words(text):
    """Comparable words. Whisper writes numbers as digits ("17h30"), drops accents its own way and expands
    'tou -> estou; none of that says anything about the audio.
    ponytail: numbers (and "e") are dropped on both sides, so a wrong number is not caught."""
    text = unicodedata.normalize("NFD", text.lower())
    text = "".join(char for char in text if not unicodedata.combining(char))
    found = [SAME.get(word, word) for word in re.findall(r"[\w']+", re.sub(r"'t(?=\w)", "est", text))]
    return [word for word in found if word not in NUMBERS and not any(char.isdigit() for char in word)]


def accuracy(expected, heard):
    a, b = words(expected), words(heard)
    return difflib.SequenceMatcher(None, a, b).ratio() if a else 1.0


def chunks(text, limit=150):
    """Sentences joined up to `limit` characters: the engine drifts on long inputs."""
    out = []
    for sentence in re.split(r"(?<=[.!?…])\s+", text):
        if out and len(out[-1]) + 1 + len(sentence) <= limit:
            out[-1] += " " + sentence
        else:
            out.append(sentence)
    return out


def spoken_lines(lines):
    """[(speaker or None, text)]: "Name: text" is a dialogue line and the name is not read aloud.
    Lines before the first name (a scene title) have no speaker."""
    out, names = [], []
    for line in lines:
        match = SPEAKER.match(line)
        if match:
            names += [match[1]] if match[1] not in names else []
            out.append((match[1], match[2]))
        elif out and out[-1][0] is not None and len(names) > 1:
            # A reply written without its name, once two people are talking: the other one answers.
            out.append((next(name for name in reversed(names) if name != out[-1][0]), line))
        else:
            out.append((None, line))
    return out


def build(lines, voices, speak=speak):
    """MP3 bytes of the lines, one voice per speaker, 0.5 s between lines."""
    speakers = list(dict.fromkeys(speaker for speaker, _ in lines))
    parts, params = [], None
    for speaker, text in lines:
        for piece in chunks(text):
            with wave.open(io.BytesIO(speak(piece, voices[speakers.index(speaker) % len(voices)],
                                            response_format="wav"))) as clip:
                params = clip.getparams()
                parts += [clip.readframes(clip.getnframes()), bytes(int(params.framerate * 0.15) * params.sampwidth)]
        parts[-1] = bytes(int(params.framerate * 0.5) * params.sampwidth)
    with tempfile.TemporaryDirectory() as tmp:
        with wave.open(f"{tmp}/in.wav", "wb") as out:
            out.setparams(params)
            out.writeframes(b"".join(parts[:-1]))
        subprocess.run([FFMPEG, "-y", "-loglevel", "error", "-i", f"{tmp}/in.wav", "-c:a", "libmp3lame",
                        "-b:a", "48k", "-ar", "24000", "-ac", "1", f"{tmp}/out.mp3"], check=True)
        return Path(f"{tmp}/out.mp3").read_bytes()


def peaks_hex(mp3, buckets=200):
    """200 loudness buckets (0-255, hex pairs): the waveform the app draws for an audio attachment."""
    raw = subprocess.run([FFMPEG, "-v", "error", "-i", str(mp3), "-ac", "1", "-ar", "8000", "-f", "s16le", "-"],
                         capture_output=True, check=True).stdout
    pcm = array.array("h")
    pcm.frombytes(raw[: len(raw) // 2 * 2])
    count = min(buckets, len(pcm))
    bars = [0] * count
    for index, value in enumerate(pcm):
        bucket = index * count // len(pcm)
        bars[bucket] = max(bars[bucket], abs(value))
    top = max(bars, default=0) or 1
    return "".join("%02x" % round(value * 255 / top) for value in bars)


def _request(route, payload=None):
    """studio() in the shape worker._load expects: full URLs or routes under /v1, JSON back."""
    root = worker.studio_root(worker.connection_credentials()[0])
    path = route[len(root):] if route.startswith(root) else "/v1" + route
    return json.loads(studio(path, payload, seconds=900))


def open_session(speech):
    """Frees the GPU (the speech engine needs about 6 GB) and loads the engine; remembers what to load back."""
    loaded = [entry["id"] for entry in _request("/models")["data"] if entry.get("loaded") is True]
    for model in loaded:
        studio("/v1/unload", {"model_path": model})
    studio("/v1/load", {"model_path": TTS_MODEL}, seconds=900)
    saved = {voice["name"]: voice["id"] for voice in _request("/audio/voices")["voices"]}
    speech.update(before=[model for model in loaded if model != TTS_MODEL], voices=[saved[name] for name in VOICES])


def close(speech):
    """Loads back the language model that was loaded before the audio jobs of this pass."""
    if speech.get("before"):
        try:
            worker._load(worker.connection_credentials()[0], _request, speech["before"][0])
        except Exception:
            pass  # the next LLM job loads its model itself


def run_job(vault, job, speech):
    """Makes the clip of a `phrase-audio` job, checks it and attaches it to the phrase note."""
    import phrase_notes

    if not speech:
        open_session(speech)
    lines = spoken_lines(job["lines"])
    text = " ".join(line for _, line in lines)
    best, score = None, -1.0
    for _ in range(4):  # the engine slurs a sentence now and then; a clip takes seconds
        mp3 = build(lines, speech["voices"])
        heard = accuracy(text, transcribe(mp3))
        if heard > score:
            best, score = mp3, heard
        if score >= PASS:
            break
    relative = f"assets/modules/{phrase_notes.MODULE}/audio/{job['phrase']}.mp3"
    target = vault / relative
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_bytes(best)
    target.with_name(target.name + ".peaks").write_text(peaks_hex(target), encoding="ascii")
    note = vault / job["note"]
    source = note.read_text(encoding="utf-8")
    line = f'#tylog.attachment("{relative}", kind: "audio")[Audio]'
    if relative not in source:
        source = re.sub(r"^(== (?:Corrected|Translation pt)\n)", lambda m: m[1] + "\n" + line + "\n", source,
                        count=1, flags=re.MULTILINE)
        note.write_text(source, encoding="utf-8")
    for path in (job["note"], relative, relative + ".peaks"):
        phrase_notes.record_file(vault, path)
    job.update(score=round(score, 2), audio=relative, sha256=hashlib.sha256(best).hexdigest())


if __name__ == "__main__":
    assert chunks("Olá. Bom dia!", 8) == ["Olá.", "Bom dia!"]
    assert spoken_lines(["Médico: Bom dia.", "Às 10:30 fui lá."]) == [("Médico", "Bom dia."), (None, "Às 10:30 fui lá.")]
    assert accuracy("Olá, bom dia!", "olá bom dia") == 1.0
    assert accuracy("'Tou às dezassete e trinta, senhor.", "Estou as 17h30, Sr.") == 1.0
    assert accuracy("Bom dia a todos", "Boa noite a todos") < 0.9
    assert spoken_lines(["Na receção", "Eu: Olá.", "Carlos: Sim.", "Ah, percebi."]) == [
        (None, "Na receção"), ("Eu", "Olá."), ("Carlos", "Sim."), ("Eu", "Ah, percebi.")]
    print("ok")
