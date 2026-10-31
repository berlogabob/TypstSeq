"""Pure pieces of the audio-notes v2 transcript pipeline.

Speech map (voice activity -> chunks), hallucination filter and sentence lines.
The worker (tool/transcribe_worker.py) owns I/O; nothing here loads a model
except speech_regions, which is only called on the Studio side.
"""

import hashlib
import json
import math
import os
import re
import zlib
from pathlib import Path

from transcribe_worker import collapse_repeats, escape_markup, format_ts

SAMPLE_RATE = 16000
MAX_COMPRESSION = 2.4  # zlib ratio above this is looping text
MIN_CHARS_FOR_RATIO = 40
BLOCKLIST = re.compile(r"^(legendas?\b|subtitles? by|amara\.org|obrigad[oa]\.?$)", re.IGNORECASE)
SENTENCE_END = re.compile(r"[.!?…]+\s+")
MIN_WORDS = 3
GAP_TEXT = "[—]"
DOUBTFUL_PREFIX = "(?) "
NOTE_LINE = re.compile(r"^\s*-\s+(\d{1,3}):([0-5]\d)\s+(.+?)\s*$")


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
    sidecar = sidecar_path(vault, audio)
    if sidecar.exists():
        return None
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
