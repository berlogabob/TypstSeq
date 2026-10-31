"""Pure pieces of the audio-notes v2 transcript pipeline.

Speech map (voice activity -> chunks), hallucination filter, sentence lines, sidecar
merge, and the v2 passes. Studio is reached only through StudioSTT (every call under
a deadline); MacSTT is the guarded Mac fallback and the only local model load. The
worker (tool/transcribe_worker.py) owns jobs and note I/O.
"""

import base64
import difflib
import hashlib
import json
import math
import os
import re
import shutil
import subprocess
import tempfile
import time
import urllib.parse
import zlib
from pathlib import Path
from urllib.request import Request, urlopen

import transcribe_worker as worker
from transcribe_worker import collapse_repeats, escape_markup, format_ts

SAMPLE_RATE = 16000
# Studio STT passes (Task 3 decision). Engine and model ids as /api/inference/audio/stt/* expects them.
PRIMARY = "whisper-large-v3-turbo"  # transformers engine; punctuated text
SECONDARY = "qwen3-asr-1.7b"        # mtmd engine; a different architecture
STUDIO_MODELS = {PRIMARY: ("transformers", "large-v3-turbo"), SECONDARY: ("mtmd", "qwen3-asr-1.7b")}
STUDIO_DEVICE = "gpu"
LOAD_CAP_S = 600
MAX_COMPRESSION = 2.4  # zlib ratio above this is looping text
MIN_CHARS_FOR_RATIO = 40
BLOCKLIST = re.compile(r"^(legendas?\b|subtitles? by|amara\.org|obrigad[oa]\.?$)", re.IGNORECASE)
SENTENCE_END = re.compile(r"[.!?…]+\s+")
MIN_WORDS = 3
GAP_TEXT = "[—]"
DOUBTFUL_PREFIX = "(?) "
NOTE_LINE = re.compile(r"^\s*-\s+(\d{1,3}):([0-5]\d)\s+(.+?)\s*$")
# A speech chunk whose two engines agree on less than this (agreement()) is doubtful.
# Set on the theatre sidecar 3efa2a81a7186a11d40eb0a34a974200b8daa505.json (2026-10-31): 151 speech
# chunks, all with asr_alt. 0.01 flags 20 of 151 = 13.2%: 18 chunks have no word in common, and 2 long
# chunks (300+ words) match once. 0.05 would flag 23 = 15.2%, just above the 10-15% target.
DOUBT_THRESHOLD = 0.01


def speech_regions(audio_path, min_silence_ms=2000):
    """Voice activity regions of a recording in seconds (faster-whisper's bundled Silero VAD)."""
    from faster_whisper import decode_audio
    from faster_whisper.vad import VadOptions, get_speech_timestamps

    audio = worker.decode_nonempty(audio_path, decode_audio)  # PyAV reads some raw .aac as 0 s
    stamps = get_speech_timestamps(audio, VadOptions(min_silence_duration_ms=min_silence_ms),
                                   sampling_rate=SAMPLE_RATE)
    return [(s["start"] / SAMPLE_RATE, s["end"] / SAMPLE_RATE) for s in stamps]


def plan_chunks(speech, total, max_len=25.0, mark_gap=5.0):
    """Speech regions -> ordered items: "speech" chunks of at most max_len and "gap" items.

    A region longer than max_len is cut into equal parts. Neighbouring pieces merge
    while the merged span stays within max_len and the pause between them is shorter
    than mark_gap. A pause of mark_gap or more is a boundary and, if it is between
    chunks or at the ends, becomes a "gap" item.
    """
    pieces = []
    for start, end in speech:
        n = math.ceil((end - start) / max_len)
        if n > 1:
            bounds = [start + (end - start) * i / n for i in range(n)] + [end]
            pieces += list(zip(bounds, bounds[1:]))
        else:
            pieces.append((start, end))
    chunks = []
    for start, end in pieces:
        if chunks and start - chunks[-1][1] < mark_gap and end - chunks[-1][0] <= max_len:
            chunks[-1] = (chunks[-1][0], end)
        else:
            chunks.append((start, end))
    items = []
    prev_end = 0.0
    for start, end in chunks:
        if start - prev_end >= mark_gap:
            items.append({"start": prev_end, "end": start, "kind": "gap"})
        items.append({"start": start, "end": end, "kind": "speech"})
        prev_end = end
    if total - prev_end >= mark_gap:
        items.append({"start": prev_end, "end": total, "kind": "gap"})
    return items


def is_hallucination(text):
    """Whisper garbage: looping text, subtitle credits, a bare "Obrigado."."""
    text = text.strip()
    if len(text) > MIN_CHARS_FOR_RATIO:
        raw = text.encode("utf-8")
        if len(raw) / len(zlib.compress(raw)) > MAX_COMPRESSION:
            return True
    if BLOCKLIST.match(text):
        return True
    return len(collapse_repeats(text)) < 0.5 * len(text)


def sentence_lines(start, end, text):
    """One recognised chunk -> [(time, sentence line)], times proportional to character offset.

    A sentence under MIN_WORDS words joins the next one; a short last sentence joins the previous.
    """
    text = text.strip()
    if not text:
        return []
    begins = [0] + [m.end() for m in SENTENCE_END.finditer(text)]
    groups = []
    for begin, stop in zip(begins, begins[1:] + [len(text)]):
        if groups and _words(text, groups[-1]) < MIN_WORDS:
            groups[-1][1] = stop
        else:
            groups.append([begin, stop])
    if len(groups) > 1 and _words(text, groups[-1]) < MIN_WORDS:
        last = groups.pop()
        groups[-1][1] = last[1]
    return [(start + (end - start) * begin / len(text), text[begin:stop].strip())
            for begin, stop in groups]


def _words(text, group):
    return len(text[group[0]:group[1]].split())


def sidecar_path(vault, audio):
    """vault/_system/jobs/segments/<sha1(audio)>.json, outside the job scan."""
    digest = hashlib.sha1(audio.encode("utf-8")).hexdigest()
    return Path(vault) / "_system/jobs/segments" / f"{digest}.json"


def load_sidecar(path):
    try:
        return json.loads(Path(path).read_text(encoding="utf-8"))
    except FileNotFoundError:
        return {"lines": [], "stages": {}}


def save_sidecar(path, data):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(path.name + ".tmp")
    tmp.write_text(json.dumps(data, ensure_ascii=False), encoding="utf-8")
    os.replace(tmp, path)


def backup_legacy(vault, audio, note_text):
    """Saves a note written before sidecars existed as <sha1>.v1.typ. Returns the path, or None if nothing was written."""
    if sidecar_path(vault, audio).exists():
        return None
    return backup_legacy_note(vault, audio, note_text)


def backup_legacy_note(vault, audio, note_text):
    """Writes <sha1>.v1.typ once, whatever the sidecar holds (v1 translations write one too).
    Returns the path, or None if the backup exists."""
    sidecar = sidecar_path(vault, audio)
    sidecar.parent.mkdir(parents=True, exist_ok=True)
    backup = sidecar.with_name(sidecar.stem + ".v1.typ")
    try:
        with backup.open("x", encoding="utf-8") as handle:
            handle.write(note_text)
    except FileExistsError:
        return None
    return backup


def merge_section(note_text, heading, lines):
    """Rewrites `== heading` from the sidecar lines. Returns (note_text, lines).

    A note line equal to a line's rendered text is that line. A rendered line whose
    note line changed in place (same mm:ss) was edited: its note text becomes the
    ground truth, status "user". A rendered line with no note line was deleted and
    stays deleted. A note line nothing claims is a user addition. Lines never
    rendered before are new and get written, except those starting inside a span
    pinned by a user line (see Edit protection): they are left out of this run.
    """
    lines = [dict(line, rendered=dict(line.get("rendered", {}))) for line in lines]
    chunks = note_text.splitlines(keepends=True)
    found = _section_range(chunks, heading)
    entries = []
    if found:
        for chunk in chunks[found[0] + 1:found[1]]:
            raw = chunk.rstrip("\r\n")
            if NOTE_LINE.match(raw):
                entries.append(raw)

    taken, matched = set(), set()
    for i, line in enumerate(lines):
        want = line["rendered"].get(heading)
        if line.get("status") == "deleted" or want is None:
            continue
        j = next((j for j, raw in enumerate(entries) if j not in taken and raw == want), None)
        if j is not None:
            taken.add(j)
            matched.add(i)
    for i, line in enumerate(lines):
        if i in matched or line.get("status") == "deleted" or heading not in line["rendered"]:
            continue
        j = next((j for j, raw in enumerate(entries)
                  if j not in taken and _seconds(raw) == int(line["start"])), None)
        if j is not None:
            taken.add(j)
            matched.add(i)
            line.update(status="user", text=_unescape(NOTE_LINE.match(entries[j])[3]))
            line["rendered"][heading] = entries[j]
    # A note line the user owns (edited, or typed by them) pins [its start, next note line's start).
    # With no next line it pins 20 s (max line length), else the rest of the run would be dropped.
    user_raw = {line["rendered"][heading] for line in lines
                if line.get("status") == "user" and heading in line["rendered"]}
    pins = [(_seconds(raw), _seconds(entries[j + 1]) if j + 1 < len(entries) else _seconds(raw) + 20)
            for j, raw in enumerate(entries) if j not in taken or raw in user_raw]
    for i, line in enumerate(lines):
        if line.get("status") == "deleted":
            continue
        if i not in matched:
            if heading in line["rendered"]:
                line["status"] = "deleted"
                continue
            if any(lo <= line["start"] < hi for lo, hi in pins):
                continue  # fresh machine line inside a user span: dropped on this run
        elif line.get("status") == "user":
            continue  # the note line is the user's text, kept verbatim
        line["rendered"][heading] = _render(line)
    for j, raw in enumerate(entries):
        if j not in taken:
            lines.append({"start": float(_seconds(raw)), "kind": "speech",
                          "text": _unescape(NOTE_LINE.match(raw)[3]), "status": "user",
                          "rendered": {heading: raw}})

    order = sorted((i for i, line in enumerate(lines)
                    if line.get("status") != "deleted" and heading in line["rendered"]),
                   key=lambda i: (lines[i]["start"], i))
    body = [lines[i]["rendered"][heading] for i in order]
    return _write_section(note_text, heading, body), lines


def _render(line):
    if line.get("kind") == "gap":
        body = GAP_TEXT
    else:
        body = escape_markup(" ".join(line["text"].split()))
        if line.get("status") == "doubtful":
            body = DOUBTFUL_PREFIX + body
    return f"- {format_ts(line['start'])} {body}"


def _seconds(raw):
    match = NOTE_LINE.match(raw)
    return int(match[1]) * 60 + int(match[2])


def _unescape(s):
    return re.sub(r"\\(.)", r"\1", s)


def _section_range(chunks, heading):
    """(index of the `== heading` line, index of the next `== ` line or len), or None."""
    for start, chunk in enumerate(chunks):
        if chunk.strip() == f"== {heading}":
            end = start + 1
            while end < len(chunks) and not chunks[end].startswith("== "):
                end += 1
            return start, end
    return None


def _write_section(note_text, heading, body):
    block = f"== {heading}\n\n" + "".join(f"{line}\n" for line in body)
    chunks = note_text.splitlines(keepends=True)
    found = _section_range(chunks, heading)
    if found is None:
        if not note_text or note_text.endswith("\n\n"):
            separator = ""
        else:
            separator = "\n" if note_text.endswith("\n") else "\n\n"
        return note_text + separator + block
    start, end = found
    tail = "".join(chunks[end:])
    return "".join(chunks[:start]) + block + ("\n" if tail else "") + tail


def section_has_lines(note_text, heading):
    chunks = note_text.splitlines(keepends=True)
    found = _section_range(chunks, heading)
    return found is not None and any(NOTE_LINE.match(chunk.rstrip("\r\n")) for chunk in chunks[found[0] + 1:found[1]])


def clear_section(note_text, heading):
    """Empties `== heading` (kept as a heading). A note without the section is returned unchanged."""
    if _section_range(note_text.splitlines(keepends=True), heading) is None:
        return note_text
    return _write_section(note_text, heading, [])


def remove_section(note_text, heading):
    """Drops `== heading` and its lines. A note without the section is returned unchanged."""
    chunks = note_text.splitlines(keepends=True)
    found = _section_range(chunks, heading)
    if found is None:
        return note_text
    start, end = found
    return "".join(chunks[:start] + chunks[end:])


def remove_section_lines(note_text, heading, raws):
    """Drops the note lines in `== heading` whose text equals one of raws exactly."""
    chunks = note_text.splitlines(keepends=True)
    found = _section_range(chunks, heading)
    if found is None or not raws:
        return note_text
    start, end = found
    return "".join(chunk for index, chunk in enumerate(chunks)
                   if not (start < index < end and chunk.rstrip("\r\n") in raws))


# Transcript lines (v2)

def audio_seconds(audio):
    ffprobe = shutil.which("ffprobe") or "/opt/homebrew/bin/ffprobe"  # launchd PATH is minimal
    out = subprocess.run([ffprobe, "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0",
                          str(audio)], capture_output=True, text=True, check=True,
                         stdin=subprocess.DEVNULL, timeout=60).stdout
    return float(out.strip())


def cut_chunk(audio, start, end, out):
    """Writes audio[start:end] (seconds) to out as 16 kHz mono WAV."""
    ffmpeg = shutil.which("ffmpeg") or "/opt/homebrew/bin/ffmpeg"
    subprocess.run([ffmpeg, "-v", "error", "-y", "-ss", f"{start:.3f}", "-i", str(audio),
                    "-t", f"{end - start:.3f}", "-vn", "-ac", "1", "-ar", "16000", "-c:a", "pcm_s16le",
                    str(out)], check=True, stdin=subprocess.DEVNULL, timeout=300)


def _gap_line(start):
    return {"start": float(start), "kind": "gap", "text": "", "status": "ok"}


def agreement(a, b):
    """How alike two recognitions of one chunk are, 0..1: difflib ratio on lowercased words, punctuation dropped."""
    return difflib.SequenceMatcher(None, _tokens(a), _tokens(b)).ratio()


def _tokens(text):
    return re.findall(r"\w+", text.lower())


def _doubtful(chunk, text):
    """Engines disagree on a speech chunk. No second text (asr_alt missing or "", as the Mac fallback
    stores it) is never doubtful."""
    alt = (chunk.get("asr_alt") or "").strip()
    return bool(alt) and agreement(text, alt) < DOUBT_THRESHOLD


def lines_from_chunks(chunks):
    """Chunks with their primary text -> Transcript lines. Gap items, empty text and hallucinations are gap lines.

    Lines of a speech chunk whose engines disagree (_doubtful) get status "doubtful".
    """
    lines = []
    for chunk in chunks:
        start = float(chunk["start"])
        text = (chunk.get("asr") or "").strip()
        if chunk["kind"] == "gap" or not text or is_hallucination(text):
            lines.append(_gap_line(start))
            continue
        status = "doubtful" if _doubtful(chunk, text) else "ok"
        lines += [{"start": at, "kind": "speech", "text": sentence, "status": status}
                  for at, sentence in sentence_lines(start, chunk["end"], text)]
    return lines


def transcribe_v2(audio, sidecar, stt, *, engines=(PRIMARY, SECONDARY)):
    """Runs the speech chunks through each engine as one pass; returns the Transcript lines.

    The speech map is planned once and stored in the sidecar. A pass calls
    stt(wav_path, engine) for each speech chunk that has no text for that engine yet
    (`asr` for PRIMARY, `asr_alt` for SECONDARY), saving the sidecar after every chunk.
    A stopped run resumes at the first chunk without text.
    """
    data = load_sidecar(sidecar)
    if "chunks" not in data:
        data["chunks"] = plan_chunks(speech_regions(audio), audio_seconds(audio))
        save_sidecar(sidecar, data)
    with tempfile.TemporaryDirectory() as tmp:
        for engine in engines:
            field = "asr" if engine == PRIMARY else "asr_alt"
            for index, chunk in enumerate(data["chunks"]):
                if chunk["kind"] != "speech" or field in chunk:
                    continue
                wav = Path(tmp) / f"chunk{index:05d}.wav"
                cut_chunk(audio, chunk["start"], chunk["end"], wav)
                chunk[field] = stt(wav, engine) or ""
                save_sidecar(sidecar, data)
    return lines_from_chunks(data["chunks"])


def reconcile_lines(previous, fresh):
    """Fresh chunk lines against the lines the last merge left (they carry `rendered`).

    A fresh line at the start of a machine line refreshes that line and keeps its rendered
    state, so merge_section rewrites it. A fresh line at the start of a user or deleted line
    is dropped. Other fresh lines are new. Returns (lines for merge_section, stale): stale
    are machine lines no fresh line replaces; their note lines must go before the merge,
    or they would come back as user lines.
    """
    by_key = {}
    for index, old in enumerate(previous):
        by_key.setdefault((old["start"], old["kind"]), []).append(index)
    claimed, lines = set(), []
    for new in fresh:
        pending = [i for i in by_key.get((new["start"], new["kind"]), []) if i not in claimed]
        if not pending:
            lines.append(dict(new, rendered={}))
            continue
        claimed.add(pending[0])
        old = previous[pending[0]]
        if old.get("status") in ("user", "deleted"):
            lines.append(dict(old, rendered=dict(old.get("rendered", {}))))
        else:
            lines.append(dict(old, text=new["text"], status=new["status"],
                              rendered=dict(old.get("rendered", {}))))
    stale = []
    for index, old in enumerate(previous):
        if index in claimed:
            continue
        if old.get("status") in ("user", "deleted"):
            lines.append(dict(old, rendered=dict(old.get("rendered", {}))))
        else:
            stale.append(old)
    return lines, stale


def finish_transcript(sidecar, lines):
    """Records the merged lines and marks the transcript stage done. Call after the note is written."""
    data = load_sidecar(sidecar)
    data["lines"] = lines
    data.setdefault("stages", {})["transcript"] = "done"
    save_sidecar(sidecar, data)


def _studio_request(root, key, method, path, body=None, *, seconds):
    """One Studio HTTP call under a wall-clock deadline as well as the socket timeout."""
    headers = {"Authorization": f"Bearer {key}"} if key else {}
    data = None
    if body is not None:
        data = json.dumps(body).encode("utf-8")
        headers["Content-Type"] = "application/json"
    request = Request(root + path, data=data, method=method, headers=headers)
    with worker.deadline(seconds), urlopen(request, timeout=seconds) as response:
        raw = response.read()
    try:
        return json.loads(raw) if raw.strip() else {}
    except ValueError:
        return {}


class StudioSTT:
    """Studio speech-to-text for the v2 passes (request shape from tool/asr_bakeoff.py).

    One engine is resident at a time: asking for another unloads the first. close() unloads
    the resident one; the caller closes after each pass.
    """

    def __init__(self, root, key, lang):
        self.root = root.rstrip("/")
        self.key = key
        self.lang = lang
        self.loaded = None
        self.language = None  # Studio's detection, used when the job has no language

    def _call(self, method, path, body=None, *, seconds):
        return _studio_request(self.root, self.key, method, path, body, seconds=seconds)

    def _status(self, engine):
        return self._call("GET", "/api/inference/audio/stt/status", seconds=30)[STUDIO_MODELS[engine][0]]

    def _load(self, engine):
        name, model = STUDIO_MODELS[engine]
        if model not in self._status(engine)["downloaded_models"]:
            raise RuntimeError(f"{model} is not downloaded on Studio")
        self._call("POST", "/api/inference/audio/stt/load",
                   {"engine": name, "model": model, "device": STUDIO_DEVICE}, seconds=LOAD_CAP_S)
        self.loaded = engine  # set before polling, so close() unloads it even if the wait fails
        started = time.monotonic()
        while True:
            status = self._status(engine)
            if status["loaded_model"] == model and not status["loading"]:
                return
            if not status["loading"]:
                raise RuntimeError(f"load finished, loaded_model={status['loaded_model']}")
            if time.monotonic() - started > LOAD_CAP_S:
                raise TimeoutError(f"{model} not loaded after {LOAD_CAP_S} s")
            time.sleep(5)

    def __call__(self, wav, engine):
        if self.loaded != engine:
            self.close()
            self._load(engine)
        name, model = STUDIO_MODELS[engine]
        reply = self._call("POST", "/api/inference/audio/transcribe", {
            "audio": base64.b64encode(Path(wav).read_bytes()).decode("ascii"),
            "engine": name, "model": model, "language": self.lang, "device": STUDIO_DEVICE,
        }, seconds=worker.STUDIO_DEADLINE)
        self.language = self.language or reply.get("language")
        return str(reply.get("text", "")).strip()

    def close(self):
        if self.loaded is None:
            return
        name, model = STUDIO_MODELS[self.loaded]
        self.loaded = None
        query = urllib.parse.urlencode({"engine": name, "model": model, "wait": "true"})
        self._call("POST", f"/api/inference/audio/stt/unload?{query}", seconds=120)


class MacSTT:
    """Mac fallback for the primary pass when Studio is missing or failed.

    faster-whisper on the CPU, model capped at small, loaded once, and only when free memory
    allows (checked at load). Runs niced. No secondary pass.
    """

    def __init__(self, model, lang, *, studio_failed=False):
        self.model_name = worker.min_model(model, worker.LOCAL_MODEL_CAP)
        self.lang = lang
        self.studio_failed = studio_failed
        self.model = None
        self.language = None

    def __call__(self, wav, engine):
        if engine != PRIMARY:
            return None
        if self.model is None:
            if not worker.mac_fallback_allowed():
                prefix = "Studio unreachable; " if self.studio_failed else ""
                raise RuntimeError(prefix + "Mac fallback refused (low memory)")
            worker.lower_priority()
            from faster_whisper import WhisperModel

            options = {"device": "cpu", "compute_type": "int8"}
            try:
                self.model = WhisperModel(self.model_name, local_files_only=True, **options)
            except OSError:
                self.model = WhisperModel(self.model_name, **options)
        segments, info = self.model.transcribe(str(wav), language=self.lang)
        self.language = self.language or info.language
        return " ".join(segment.text.strip() for segment in segments)


# Context pass (Stage 5): Summary, Scenes, References from the transcript and the user's Context

CONTEXT_WINDOW = 400  # speech lines per LLM call; longer transcripts go in windows
GENERATED = ("Summary", "Scenes", "References")
SECTION_ORDER = ("Context", "Summary", "Scenes", "References", "Comments", "Transcript")


def section_text(note_text, heading):
    """Body of `== heading` (stripped), or "" when the section is missing."""
    chunks = note_text.splitlines(keepends=True)
    found = _section_range(chunks, heading)
    if found is None:
        return ""
    return "".join(chunks[found[0] + 1:found[1]]).strip()


def context_messages(context_text, target, window):
    """Prompt for one window of numbered speech lines [(number, text)]. The reply is one JSON object (parse_context_reply)."""
    language = worker.LANGUAGE_NAMES.get(target, target)
    schema = ('{"summary": string, "scenes": [{"line": int, "title": string}], '
              f'"glossary": [{{"term": string, "spelling": string, "{target}": string}}], '
              '"references": [{"line": int, "term": string, "explanation": string}]}')
    system = (
        "You read the transcript of one audio recording. Reply with one JSON object and nothing else: "
        f"{schema}. "
        f"Write the summary, scene titles, glossary renderings and explanations in {language}. "
        "summary: 5 to 10 sentences on what the recording is and what happens in it. "
        "scenes: each place where the subject or scene changes, with the number of its first line and a short title. "
        "glossary: names and terms the transcript uses; spelling is the form the transcript uses. "
        "references: allusions, quotations, places and names a listener may not know, with the number of the line "
        "where each occurs and a one or two sentence explanation. "
        "Use only line numbers from the input. Add nothing that is neither in the transcript nor in the Context. "
        "The Context is written by the user (programme, cast, notes); use it for names and spelling."
    )
    transcript = "\n".join(f"[{number}] {text}" for number, text in window)
    user = f"Context:\n{context_text or '(none)'}\n\nTranscript:\n{transcript}"
    return [{"role": "system", "content": system}, {"role": "user", "content": user}]


def summary_messages(target, summaries):
    """Prompt that merges the window summaries of a long transcript into one."""
    language = worker.LANGUAGE_NAMES.get(target, target)
    system = (f"Combine the partial summaries of one recording into one summary of 5 to 10 sentences in {language}. "
              'Reply with one JSON object and nothing else: {"summary": string}.')
    return [{"role": "system", "content": system}, {"role": "user", "content": "\n\n".join(summaries)}]


def _json_object(reply):
    text = reply.strip()
    if text.startswith("```"):
        text = re.sub(r"^```[^\n]*\n", "", text)
        text = re.sub(r"\s*```$", "", text)
    try:
        value = json.loads(text)
    except ValueError as error:
        raise ValueError(f"Context reply is not JSON: {error}") from None
    if not isinstance(value, dict):
        raise ValueError("Context reply is not a JSON object")
    return value


def _items(value, key):
    items = value.get(key, [])
    if not isinstance(items, list):
        raise ValueError(f"Context reply: {key} is not a list")
    return [item for item in items if isinstance(item, dict)]


def _text(item, key):
    value = item.get(key)
    return value.strip() if isinstance(value, str) and value.strip() else None


def _line_number(item, numbers):
    number = item.get("line")
    return number if type(number) is int and number in numbers else None


def parse_context_reply(reply, numbers, target):
    """One window's reply -> {"summary", "scenes", "glossary", "references"}; `numbers` are the line numbers shown.

    A malformed reply raises ValueError. An item with a bad line number or missing text is dropped; the rest is kept.
    """
    value = _json_object(reply)
    summary = value.get("summary")
    if not isinstance(summary, str):
        raise ValueError("Context reply: summary is not a string")
    scenes, glossary, references = [], [], []
    for item in _items(value, "scenes"):
        number, title = _line_number(item, numbers), _text(item, "title")
        if number is not None and title:
            scenes.append({"line": number, "title": title})
    for item in _items(value, "glossary"):
        term, rendering = _text(item, "term"), _text(item, target)
        if term and rendering:
            glossary.append({"term": term, "spelling": _text(item, "spelling") or term, target: rendering})
    for item in _items(value, "references"):
        number, term = _line_number(item, numbers), _text(item, "term")
        explanation = _text(item, "explanation")
        if number is not None and term and explanation:
            references.append({"line": number, "term": term, "explanation": explanation})
    return {"summary": summary.strip(), "scenes": scenes, "glossary": glossary, "references": references}


def parse_summary_reply(reply):
    summary = _json_object(reply).get("summary")
    if not isinstance(summary, str):
        raise ValueError("Context reply: summary is not a string")
    return summary.strip()


def context_pass(speech, context_text, target, chat):
    """Stage 5 over the speech lines (dicts with `text`, numbered from 1). chat(messages) returns the reply text.

    Returns {"summary", "scenes", "glossary", "references"}; scene and reference line numbers are the
    speech line numbers. Transcripts longer than CONTEXT_WINDOW lines go in windows, and the window
    summaries are merged by one more call. No speech lines: no call.
    """
    numbered = [(number, line["text"]) for number, line in enumerate(speech, start=1)]
    if not numbered:
        return {"summary": "", "scenes": [], "glossary": [], "references": []}
    parts = []
    for first in range(0, len(numbered), CONTEXT_WINDOW):
        window = numbered[first:first + CONTEXT_WINDOW]
        reply = chat(context_messages(context_text, target, window))
        parts.append(parse_context_reply(reply, {number for number, _ in window}, target))
    if len(parts) == 1:
        return parts[0]
    summary = parse_summary_reply(chat(summary_messages(target, [part["summary"] for part in parts])))
    glossary, seen = [], set()
    for entry in (entry for part in parts for entry in part["glossary"]):
        if entry["term"].lower() not in seen:
            seen.add(entry["term"].lower())
            glossary.append(entry)
    return {
        "summary": summary,
        "scenes": sorted((s for part in parts for s in part["scenes"]), key=lambda s: s["line"]),
        "glossary": glossary,
        "references": sorted((r for part in parts for r in part["references"]), key=lambda r: r["line"]),
    }


def _insert_section(note_text, heading):
    """Adds an empty `== heading` above the first section that follows it in SECTION_ORDER, so generated
    sections sit above the transcript. With none of those in the note, merge_section appends it."""
    later = {f"== {name}" for name in SECTION_ORDER[SECTION_ORDER.index(heading) + 1:]}
    chunks = note_text.splitlines(keepends=True)
    for index, chunk in enumerate(chunks):
        if chunk.strip() in later:
            separator = "" if index == 0 or chunks[index - 1].strip() == "" else "\n"
            return "".join(chunks[:index]) + separator + f"== {heading}\n\n" + "".join(chunks[index:])
    return note_text


def merge_generated(note_text, heading, items, previous):
    """Rewrites `== heading` from generated items [(start seconds, text)]. Returns (note_text, lines).

    `previous` is the line list the last run left for this heading, None when there is none (first run,
    or the section was removed). Lines keep their rendered state, so an edit the user made in the note
    survives a re-run, and a line the user deleted stays deleted (merge_section). Generated lines that no
    item produces any more are removed first, so merge_section does not read them back as user lines.
    """
    found = _section_range(note_text.splitlines(keepends=True), heading)
    if found is None:
        if not items:
            return note_text, []
        previous = None
        note_text = _insert_section(note_text, heading)
    by_start = {}
    for line in previous or []:
        by_start.setdefault(int(line["start"]), []).append(line)
    built = []
    for start, text in items:
        queue = by_start.get(int(start))
        old = queue.pop(0) if queue else None
        if old is not None and old.get("status") in ("user", "deleted"):
            built.append(old)
        else:
            built.append({"start": float(start), "kind": "speech", "text": text, "status": "ok",
                          "rendered": dict(old.get("rendered", {})) if old else {}})
    if found is not None and previous is None:
        note_text = clear_section(note_text, heading)
    elif found is not None:
        stale = {line["rendered"][heading] for queue in by_start.values() for line in queue
                 if line.get("status") not in ("user", "deleted") and heading in line.get("rendered", {})}
        note_text = remove_section_lines(note_text, heading, stale)
    return merge_section(note_text, heading, built)


def render_context(note_text, previous, result, speech):
    """Writes Summary, Scenes and References from a context result. Returns (note_text, {heading: lines}).

    `speech` are the speech lines the result's line numbers count; `previous` maps each heading to the lines
    the last run stored. The Context section is never touched.
    """
    def at(number):
        return speech[number - 1]["start"]

    summary = result["summary"].strip()
    items = {
        "Summary": [(0.0, summary)] if summary else [],
        "Scenes": [(at(scene["line"]), scene["title"]) for scene in result["scenes"]],
        "References": [(at(ref["line"]), f"{ref['term']} -- {ref['explanation']} (AI)")
                       for ref in result["references"]],
    }
    sections = {}
    for heading in GENERATED:
        note_text, sections[heading] = merge_generated(note_text, heading, items[heading], previous.get(heading))
    return note_text, sections
