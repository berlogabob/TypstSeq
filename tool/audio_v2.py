"""Pure pieces of the audio-notes v2 transcript pipeline.

Speech map (voice activity -> chunks), hallucination filter and sentence lines.
The worker (tool/transcribe_worker.py) owns I/O; nothing here loads a model
except speech_regions, which is only called on the Studio side.
"""

import math
import re
import zlib

from transcribe_worker import collapse_repeats

SAMPLE_RATE = 16000
MAX_COMPRESSION = 2.4  # zlib ratio above this is looping text
MIN_CHARS_FOR_RATIO = 40
BLOCKLIST = re.compile(r"^(legendas?\b|subtitles? by|amara\.org|obrigad[oa]\.?$)", re.IGNORECASE)
SENTENCE_END = re.compile(r"[.!?…]+\s+")
MIN_WORDS = 3


def speech_regions(audio_path, min_silence_ms=2000):
    """Voice activity regions of a recording in seconds (faster-whisper's bundled Silero VAD)."""
    from faster_whisper import decode_audio
    from faster_whisper.vad import VadOptions, get_speech_timestamps

    audio = decode_audio(str(audio_path), sampling_rate=SAMPLE_RATE)
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
