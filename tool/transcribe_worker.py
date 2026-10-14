"""Process queued audio transcription jobs in a vault."""

import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
from urllib.request import Request, urlopen


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

    segments, info = WhisperModel(model).transcribe(str(audio), language=lang or None)
    return [(segment.start, segment.text.strip()) for segment in segments], info.language


def translate(texts, source_lang, target):
    base = os.environ.get("TYLOG_LLM_URL")
    key = os.environ.get("TYLOG_LLM_KEY")
    if not base or not key:
        config_path = Path.home() / ".pi/agent/models.json"
        studio = (json.loads(config_path.read_text(encoding="utf-8"))
                  .get("providers", {}).get("studio", {})) if config_path.exists() else {}
        base = base or studio.get("baseUrl")
        key = key or studio.get("apiKey")
    if not base:
        raise ValueError("Set TYLOG_LLM_URL or configure provider studio in ~/.pi/agent/models.json")

    def request(route, payload=None):
        headers = {"Content-Type": "application/json"}
        if key:
            headers["Authorization"] = f"Bearer {key}"
        data = json.dumps(payload).encode("utf-8") if payload is not None else None
        with urlopen(Request(base.rstrip("/") + route, data=data, headers=headers), timeout=120) as response:
            return json.load(response)

    model = os.environ.get("TYLOG_LLM_MODEL")
    if not model:
        model = next((entry["id"] for entry in request("/models")["data"]
                      if entry.get("loaded") is True), None)
        if not model:
            raise ValueError("No loaded model found; set TYLOG_LLM_MODEL")
    translated = []
    for start in range(0, len(texts), 40):
        batch = texts[start:start + 40]
        reply = request("/chat/completions", {
            "model": model,
            "temperature": 0,
            "messages": [
                {"role": "system", "content": (
                    f"Translate faithfully from {source_lang} to {target}. Keep names. "
                    "No commentary. Input is a JSON array of strings; return only a JSON "
                    "array of translated strings of the same length, in the same order."
                )},
                {"role": "user", "content": json.dumps(batch, ensure_ascii=False)},
            ],
        })["choices"][0]["message"]["content"].strip()
        if reply.startswith("```"):
            reply = re.sub(r"^```[^\n]*\n", "", reply)
            reply = re.sub(r"\s*```$", "", reply)
        result = json.loads(reply)
        if not isinstance(result, list) or len(result) != len(batch) or not all(
            isinstance(text, str) for text in result
        ):
            raise ValueError("Translation reply must be a JSON array of strings with the same length")
        translated.extend(result)
    return translated


def apply_translation(note_text, source_lang, target, translate):
    lines = note_text.splitlines(keepends=True)

    def section_bounds(heading):
        for start, line in enumerate(lines):
            if line.rstrip("\r\n") == heading:
                end = start + 1
                while end < len(lines) and not lines[end].startswith("== "):
                    end += 1
                return start, end
        return None

    transcript = section_bounds("== Transcript")
    if transcript is None:
        raise ValueError("Note has no Transcript section")
    segments = []
    for line in lines[transcript[0] + 1:transcript[1]]:
        match = re.fullmatch(r"- (\d{2,}:[0-5]\d) (.*)", line.rstrip("\r\n"))
        if match:
            segments.append((match[1], re.sub(r"\\(.)", r"\1", match[2])))
    translated = translate([text for _, text in segments], source_lang, target)
    if len(translated) != len(segments):
        raise ValueError("Translation reply must have the same length as the transcript")
    section = f"== Translation {target}\n\n" + "".join(
        f"- {timestamp} {escape_markup(text)}\n"
        for (timestamp, _), text in zip(segments, translated)
    )
    existing = section_bounds(f"== Translation {target}")
    start, end = existing if existing else (transcript[1], transcript[1])
    prefix = "".join(lines[:start])
    separator = "\n" if prefix and not prefix.endswith("\n") else ""
    return prefix + separator + section + "".join(lines[end:])


def _vault_path(vault, relative):
    path = (vault / relative).resolve()
    if Path(relative).is_absolute() or not path.is_relative_to(vault):
        raise ValueError(f"Path must be inside the vault: {relative}")
    return path


def _read_json(path):
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
        return value if isinstance(value, dict) else {}
    except (FileNotFoundError, ValueError):
        return {}


def _has_pending_jobs(vault):
    for kind in ("transcripts", "translations"):
        for path in (vault / "_system/jobs" / kind).glob("*.json"):
            if _read_json(path).get("status") in ("queued", "processing"):
                return True
    return False


def sweep(vault, now, state, force=False):
    vault = Path(vault).resolve()
    audio_settings = _read_json(vault / "_system/settings/processing.json").get("audio", {})
    if not audio_settings.get("transcribe"):
        return 0
    local_now = now.astimezone()
    today = local_now.date().isoformat()
    scheduled = False
    time = audio_settings.get("time", "")
    if audio_settings.get("scheduled") and re.fullmatch(r"(?:[01]\d|2[0-3]):[0-5]\d", time):
        scheduled = (local_now.strftime("%H:%M") >= time
                     and state.get("last_scheduled_date") != today)
    if not (force or audio_settings.get("on_the_fly") or scheduled):
        return 0

    def section(text, heading):
        match = re.search(r"^" + re.escape(heading) + r"\r?$(.*?)(?=^== |\Z)",
                          text, re.MULTILINE | re.DOTALL)
        return match.group(1) if match else None

    created = 0

    def enqueue(kind, key, job):
        nonlocal created
        path = vault / "_system/jobs" / kind / (hashlib.sha1(key.encode("utf-8")).hexdigest() + ".json")
        path.parent.mkdir(parents=True, exist_ok=True)
        try:
            with path.open("x", encoding="utf-8") as stream:
                json.dump({**job, "requested_at": now.astimezone(timezone.utc).isoformat(),
                           "status": "queued", "auto": True}, stream, ensure_ascii=False, indent=2)
                stream.write("\n")
            created += 1
        except FileExistsError:
            pass

    for note in sorted((vault / "notes").glob("Audio *.typ")):
        text = note.read_text(encoding="utf-8")
        header = re.search(r'#show:\s*tylog\.note\.with\(((?:"(?:\\.|[^"\\])*"|[^")])*)\)',
                           text, re.DOTALL)
        if not header or not re.search(r'\bkind:\s*"audio"', header.group(1)):
            continue
        attachment = re.search(r'#tylog\.attachment\(\s*"((?:\\.|[^"\\])*)"\s*,\s*kind:\s*"audio"\s*\)', text)
        if not attachment:
            continue
        audio = re.sub(r"\\(.)", r"\1", attachment.group(1)).lstrip("/")
        try:
            if not _vault_path(vault, audio).is_file():
                continue
        except ValueError:
            continue
        job = {"audio": audio, "note": note.relative_to(vault).as_posix()}
        transcript = section(text, "== Transcript")
        if not transcript or not transcript.strip():
            enqueue("transcripts", audio, job)
            continue
        source_lang = _read_json(vault / "_system/jobs/transcripts" /
                                 (hashlib.sha1(audio.encode("utf-8")).hexdigest() + ".json")).get("lang")
        if source_lang:
            for target in audio_settings.get("translate_to", []):
                if target != source_lang and section(text, f"== Translation {target}") is None:
                    enqueue("translations", audio + "\n" + target,
                            {**job, "target": target, "source_lang": source_lang})
    # The scheduled run stays open until a sweep finds nothing new and nothing
    # queued or running: translations only appear after their transcripts
    # finish, so closing after the first sweep would push them to tomorrow.
    if scheduled and created == 0 and not _has_pending_jobs(vault):
        state["last_scheduled_date"] = today
    return created


def run_once(vault, model="small", translate=translate, *, now=None, state_path=None):
    vault = Path(vault).resolve()
    now = now if now is not None else datetime.now()
    state_path = Path(state_path).expanduser() if state_path is not None else Path.home() / ".tylog-transcribe-state.json"
    state = _read_json(state_path)
    requested_at = _read_json(vault / "_system/jobs/process-now.json").get("requested_at")
    force = bool(requested_at) and requested_at != state.get("last_process_now")
    sweep(vault, now, state, force=force)
    if force:
        state["last_process_now"] = requested_at
    state_path.parent.mkdir(parents=True, exist_ok=True)
    state_path.write_text(json.dumps(state, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    jobs = [(kind, path) for kind in ("transcripts", "translations")
            for path in sorted((vault / "_system/jobs" / kind).glob("*.json"))]
    for kind, job_path in jobs:
        job = json.loads(job_path.read_text(encoding="utf-8"))
        if job.get("status") != "queued":
            continue
        try:
            job["status"] = "processing"
            job_path.write_text(json.dumps(job, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
            note = _vault_path(vault, job["note"])
            with note.open(encoding="utf-8", newline="") as stream:
                note_text = stream.read()
            if kind == "transcripts":
                audio = _vault_path(vault, job["audio"])
                segments, language = transcribe(audio, model=model, lang=job.get("lang") or None)
                updated_note = apply_transcript(note_text, segments)
            else:
                updated_note = apply_translation(note_text, job["source_lang"], job["target"], translate)
            with note.open("w", encoding="utf-8", newline="") as stream:
                stream.write(updated_note)
            if kind == "transcripts":
                job["lang"] = language
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
    parser.add_argument("--state", type=Path, default=Path.home() / ".tylog-transcribe-state.json")
    args = parser.parse_args(argv)
    run_once(args.vault, model=args.model, state_path=args.state)


if __name__ == "__main__":
    main()
