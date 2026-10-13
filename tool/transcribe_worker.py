"""Process queued audio transcription jobs in a vault."""

import argparse
from datetime import datetime, timezone
import json
from pathlib import Path


def escape_markup(s):
    return "".join("\\" + char if char in "\\#[]$*_@" else char for char in s)


def format_ts(seconds):
    minutes, seconds = divmod(int(seconds), 60)
    return f"{minutes:02d}:{seconds:02d}"


def render_section(segments):
    return "== Transcript\n\n" + "".join(
        f"- {format_ts(start)} {escape_markup(text)}\n" for start, text in segments
    )


def apply_transcript(note_text, segments):
    section = render_section(segments)
    lines = note_text.splitlines(keepends=True)
    for start, line in enumerate(lines):
        if line.rstrip("\r\n") == "== Transcript":
            end = start + 1
            while end < len(lines) and not lines[end].startswith("== "):
                end += 1
            return "".join(lines[:start]) + section + "".join(lines[end:])
    separator = "" if not note_text or note_text.endswith("\n\n") else (
        "\n" if note_text.endswith("\n") else "\n\n"
    )
    return note_text + separator + section


def transcribe(audio, model="small", lang=None):
    from faster_whisper import WhisperModel

    segments, _ = WhisperModel(model).transcribe(str(audio), language=lang)
    return [(segment.start, segment.text.strip()) for segment in segments]


def _vault_path(vault, relative):
    path = (vault / relative).resolve()
    if Path(relative).is_absolute() or not path.is_relative_to(vault):
        raise ValueError(f"Path must be inside the vault: {relative}")
    return path


def run_once(vault, model="small", lang=None):
    vault = Path(vault).resolve()
    for job_path in sorted((vault / "_system/jobs/transcripts").glob("*.json")):
        job = json.loads(job_path.read_text(encoding="utf-8"))
        if job.get("status") != "queued":
            continue
        try:
            job["status"] = "processing"
            job_path.write_text(json.dumps(job, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
            audio = _vault_path(vault, job["audio"])
            note = _vault_path(vault, job["note"])
            segments = transcribe(audio, model=model, lang=lang)
            with note.open(encoding="utf-8", newline="") as stream:
                note_text = stream.read()
            updated_note = apply_transcript(note_text, segments)
            with note.open("w", encoding="utf-8", newline="") as stream:
                stream.write(updated_note)
            job["status"] = "done"
            job["finished_at"] = datetime.now(timezone.utc).isoformat()
            job.pop("error", None)
        except Exception as error:
            job["status"] = "failed"
            job["error"] = str(error)
        job_path.write_text(json.dumps(job, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--vault", required=True, type=Path)
    parser.add_argument("--once", required=True, action="store_true")
    parser.add_argument("--model", default="small")
    parser.add_argument("--lang")
    args = parser.parse_args(argv)
    run_once(args.vault, model=args.model, lang=args.lang)


if __name__ == "__main__":
    main()
