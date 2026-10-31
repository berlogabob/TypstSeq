"""Quality metrics for an audio note's transcript and translations.

Reads the format written by lib/audio/audio_note_doc.dart: `== Transcript` and
`== Translation <lang>` sections of `- mm:ss text` lines, aligned by position.
Parsing mirrors `_parseSection` there (sorted by timestamp, `\\x` unescaped).

Usage: uv run --no-project python tool/audio_metrics.py <note.typ> [sidecar.json]
The sidecar adds mean_score per language when it holds review scores.
"""

import json
import re
import sys
from pathlib import Path

FAILED = "[sem tradução]"
DOUBTFUL = "(?) "
END_OK = (".", "!", "?", "…", '"', "»")
MIN_LOOP_WORDS = 20
MAX_LOOP_UNIQUE_RATIO = 0.25
MIN_RU_CYRILLIC = 5

COMMENT_LINE = re.compile(r"^\s*-\s+([0-9]{1,3}):([0-5][0-9])\s+(.+?)\s*$")
TRANSLATION_HEADING = re.compile(r"^== Translation (\S+)\s*$", re.M)
MARKER = re.compile(r"\[[^\]]+\]")
CYRILLIC = re.compile(r"[Ѐ-ӿ]")
WORD = re.compile(r"\w+")


def _unescape(s):
    return re.sub(r"\\(.)", r"\1", s)


def _section(lines, heading):
    start = next((i for i, line in enumerate(lines) if line.strip() == f"== {heading}"), None)
    if start is None:
        return None
    end = start + 1
    while end < len(lines) and not lines[end].startswith("== "):
        end += 1
    return start + 1, end


def _entries(source, heading):
    lines = source.split("\n")
    rng = _section(lines, heading)
    if rng is None:
        return []
    timed = []
    for line in lines[rng[0] : rng[1]]:
        m = COMMENT_LINE.match(line)
        if m:
            ms = (int(m[1]) * 60 + int(m[2])) * 1000
            timed.append((ms, _unescape(m[3])))
    timed.sort(key=lambda entry: entry[0])
    return [text for _, text in timed]


def _is_marker(text):
    return MARKER.fullmatch(text) is not None


def _is_loop(text):
    words = WORD.findall(text.lower())
    return len(words) > MIN_LOOP_WORDS and len(set(words)) / len(words) < MAX_LOOP_UNIQUE_RATIO


def _translation_stats(lang, lines, source):
    stats = {"lines": len(lines), "untranslated": 0, "failed": 0}
    for i, text in enumerate(lines):
        if text.removeprefix(DOUBTFUL) == FAILED:  # a (?) mark on a failed line keeps it failed
            stats["failed"] += 1
        elif _is_marker(text):
            continue
        elif lang == "ru":
            if len(CYRILLIC.findall(text)) < MIN_RU_CYRILLIC:
                stats["untranslated"] += 1
        elif i < len(source) and text == source[i]:
            stats["untranslated"] += 1
    return stats


def _mean_score(sidecar, lang):
    """Mean of the review scores the sidecar holds for `lang`, rounded to 2 places; None without scores."""
    entry = (sidecar or {}).get("translations", {}).get(lang)
    scores = entry.get("scores") if isinstance(entry, dict) else None
    values = list(scores.values()) if isinstance(scores, dict) else []
    return round(sum(values) / len(values), 2) if values else None


def note_metrics(note_text, sidecar=None):
    source = _entries(note_text, "Transcript")
    loops = mid_cut = nonspeech = doubtful = 0
    for text in source:
        if _is_loop(text):
            loops += 1
        if _is_marker(text) and text != FAILED:
            nonspeech += 1
        elif not text.endswith(END_OK):
            mid_cut += 1
        if text.startswith(DOUBTFUL):
            doubtful += 1
    langs = dict.fromkeys(m[1] for m in TRANSLATION_HEADING.finditer(note_text))
    translations = {
        lang: _translation_stats(lang, _entries(note_text, f"Translation {lang}"), source)
        for lang in langs
    }
    for lang, stats in translations.items():
        mean = _mean_score(sidecar, lang)
        if mean is not None:
            stats["mean_score"] = mean
    return {
        "lines": len(source),
        "loops": loops,
        "mid_cut": mid_cut,
        "nonspeech": nonspeech,
        "doubtful": doubtful,
        "translations": translations,
    }


def main(argv):
    if len(argv) not in (2, 3):
        print("usage: audio_metrics.py <note.typ> [sidecar.json]", file=sys.stderr)
        return 2
    text = Path(argv[1]).read_text(encoding="utf-8")
    sidecar = json.loads(Path(argv[2]).read_text(encoding="utf-8")) if len(argv) == 3 else None
    print(json.dumps(note_metrics(text, sidecar)))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
