"""Process queued audio transcription jobs in a vault."""

import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import socket
import time
from urllib.request import Request, urlopen


KEYS_PATH = Path.home() / ".tylog/keys.json"


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
    from faster_whisper import WhisperModel, decode_audio

    model = WhisperModel(model)
    segments, info = model.transcribe(str(audio), language=lang or None,
                                      **({"multilingual": True} if not lang else {}))
    segments = list(segments)
    languages = [lang] if lang else [info.language]
    if not lang:
        try:
            windows = {}
            for segment in segments:
                window = int(segment.start // 30)
                windows[window] = windows.get(window, 0) + segment.end - segment.start
            samples = decode_audio(str(audio), sampling_rate=16000)
            weights = {}
            for window, duration in windows.items():
                detected, _, _ = model.detect_language(
                    audio=samples[window * 30 * 16000:(window + 1) * 30 * 16000])
                weights[detected] = weights.get(detected, 0) + duration
            total = sum(windows.values())
            languages += [language for language in sorted(weights, key=weights.get, reverse=True)
                          if language != info.language and weights[language] >= 0.15 * total]
        except Exception:
            languages = [info.language]
    return [(segment.start, segment.text.strip()) for segment in segments], info.language, languages


def ensure_model(base, key, prefer, request):
    """Select Ornith or load the preferred model using the authenticated request."""
    try:
        loaded = [entry["id"] for entry in request("/models")["data"]
                  if entry.get("loaded") is True]
        if prefer in loaded:
            return prefer
        ornith = next((model for model in loaded if "ornith" in model.lower()), None)
        if ornith:
            return ornith
        root = base.rstrip("/").rsplit("/v1", 1)[0]
        local = request(root + "/api/models/local")["models"]
        reference = next((entry["id"] for entry in local
                          if entry.get("model_id") == prefer), prefer)
        result = request(base.rstrip("/") + "/load", {"model_path": reference, "max_seq_length": 65536})
        if result.get("error") or result.get("success") is False:
            raise ValueError(f"Studio rejected load: {result}")
        deadline = time.monotonic() + 15 * 60
        while time.monotonic() < deadline:
            if any(entry["id"] == prefer and entry.get("loaded") is True
                   for entry in request("/models")["data"]):
                return prefer
            time.sleep(min(5, max(0, deadline - time.monotonic())))
        raise ValueError("not loaded after 15 minutes")
    except Exception as error:
        raise ValueError(f"Could not load preferred translation model {prefer}: {error}") from error


def translate(texts, source_lang, target, source_langs=None, *, settings=None):
    translate.last_model = None
    settings = settings or {}
    task = settings.get("tasks", {}).get("translate", {})
    connection = next((entry for entry in settings.get("connections", [])
                       if entry["id"] == task.get("connection")), None)
    if task.get("connection") and connection is None:
        raise ValueError(f"Unknown translation connection: {task['connection']}")
    base, key = connection_credentials(connection)
    if not base:
        raise ValueError("Set TYLOG_LLM_URL or configure provider studio in ~/.pi/agent/models.json")

    def request(route, payload=None):
        headers = {"Content-Type": "application/json"}
        if key:
            headers["Authorization"] = f"Bearer {key}"
        data = json.dumps(payload).encode("utf-8") if payload is not None else None
        url = route if route.startswith(("http://", "https://")) else base.rstrip("/") + route
        with urlopen(Request(url, data=data, headers=headers),
                     timeout=900 if route.endswith("/load") else 120) as response:
            return json.load(response)

    model = os.environ.get("TYLOG_LLM_MODEL") or task.get("model")
    if not model:
        model = ensure_model(base, key, os.environ.get("TYLOG_LLM_PREFER") or
                             ("ollama/ornith-1.5:9b" if task.get("quality") == "fast"
                              else "ollama/ornith-1.5:35b"),
                             request)
    translated = []
    for start in range(0, len(texts), 40):
        batch = texts[start:start + 40]
        reply = request("/chat/completions", {
            "model": model,
            "temperature": 0,
            "messages": [
                {"role": "system", "content": (
                    f"Translate faithfully into {target}. Keep names. "
                    "Segments that are already in the target language must be returned unchanged. "
                    f"The source may mix these languages: {', '.join(source_langs or [source_lang])}. "
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
    translate.last_model = model
    return translated


def apply_translation(note_text, source_lang, target, translate, source_langs=None):
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
    translated = translate([text for _, text in segments], source_lang, target,
                           source_langs or [source_lang])
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


def load_ai_settings(vault):
    """Read the supported settings schema, ignoring malformed/unknown fields."""
    try:
        value = _read_json(Path(vault) / "_system/settings/ai.json")
    except OSError:
        return {}
    if value.get("schema") != 1:
        return {}
    tasks = value.get("tasks")
    tasks = tasks if isinstance(tasks, dict) else {}
    clean_tasks = {}
    for name in ("transcribe", "translate"):
        task = tasks.get(name)
        if isinstance(task, dict):
            clean_tasks[name] = {key: item for key, item in task.items()
                                 if key in ("quality", "model", "connection")
                                 and isinstance(item, str) and item}
    connections = value.get("connections")
    connections = connections if isinstance(connections, list) else []
    return {"schema": 1, "tasks": clean_tasks,
            "connections": [entry for entry in connections if isinstance(entry, dict)
                            and isinstance(entry.get("id"), str) and entry["id"]
                            and isinstance(entry.get("url"), str) and entry["url"]]}


def resolve_whisper_model(settings, cli_model=None):
    task = settings.get("tasks", {}).get("transcribe", {})
    return cli_model or task.get("model") or {
        "fast": "small", "balanced": "large-v3-turbo", "best": "large-v3"
    }.get(task.get("quality"), "large-v3")


def connection_credentials(connection=None):
    provider_id = connection["id"] if connection else "studio"
    providers = _read_json(Path.home() / ".pi/agent/models.json").get("providers", {})
    provider = providers.get(provider_id, {}) if isinstance(providers, dict) else {}
    provider = provider if isinstance(provider, dict) else {}
    base = connection["url"] if connection else (
        os.environ.get("TYLOG_LLM_URL") or provider.get("baseUrl"))
    key = os.environ.get("TYLOG_LLM_KEY")
    if connection and not key:
        env_name = "TYLOG_KEY_" + re.sub(r"[^A-Z0-9]", "_", provider_id.upper())
        key = os.environ.get(env_name)
        if not key:
            local_key = _read_json(KEYS_PATH).get(provider_id)
            key = local_key if isinstance(local_key, str) else None
    return base, key or provider.get("apiKey")


def probe_connection(base, key):
    headers = {"Authorization": f"Bearer {key}"} if key else {}
    with urlopen(Request(base.rstrip("/") + "/models", headers=headers), timeout=3) as response:
        entries = json.load(response)["data"]
    return {"reachable": True, "loaded": [entry["id"] for entry in entries
            if isinstance(entry.get("id"), str) and entry.get("loaded", True) is True]}


def write_heartbeat(vault, settings, state, state_path, now, hostname, probe):
    """Best effort presence and cached connection health; never break jobs."""
    try:
        host = hostname()
        filename = re.sub(r"[^A-Za-z0-9_.-]", "_", host).strip(".") or "unknown"
        now = now.astimezone(timezone.utc)
        connections = {}
        cache = state.setdefault("connection_probes", {}) if settings.get("connections") else {}
        for connection in settings.get("connections", []):
            identifier = connection["id"]
            previous = cache.get(identifier, {})
            age = now.timestamp() - previous.get("last_probe", 0)
            if previous.get("url") != connection["url"] or not 0 <= age < 300:
                try:
                    result = probe(*connection_credentials(connection))
                except Exception:
                    result = {"reachable": False, "loaded": []}
                previous = {"url": connection["url"], "last_probe": now.timestamp(),
                            "result": result}
                cache[identifier] = previous
            connections[identifier] = previous["result"]
        prefix = "models--Systran--faster-whisper-"
        hub = Path.home() / ".cache/huggingface/hub"
        models = sorted(path.name[len(prefix):] for path in hub.glob(prefix + "*")
                        if path.is_dir())
        heartbeat = {"host": host, "last_seen": now.isoformat(),
                     "whisper_models": models, "connections": connections}
        state_path.write_text(json.dumps(state, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        directory = vault / "_system/workers"
        directory.mkdir(parents=True, exist_ok=True)
        (directory / (filename + ".json")).write_text(
            json.dumps(heartbeat, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    except Exception:
        pass


def _has_pending_jobs(vault):
    for kind in ("transcripts", "translations"):
        for path in (vault / "_system/jobs" / kind).glob("*.json"):
            if _read_json(path).get("status") in ("queued", "processing"):
                return True
    return False


def sweep(vault, now, state, force=False):
    vault = Path(vault).resolve()
    audio_settings = _read_json(vault / "_system/settings/processing.json").get("audio", {})
    transcribe_enabled = audio_settings.get("transcribe", False)
    targets = audio_settings.get("translate_to", [])
    translate_enabled = audio_settings.get("translate", bool(targets))
    if not (transcribe_enabled or translate_enabled):
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
            if transcribe_enabled:
                enqueue("transcripts", audio, job)
            continue
        source = _read_json(vault / "_system/jobs/transcripts" /
                            (hashlib.sha1(audio.encode("utf-8")).hexdigest() + ".json"))
        source_lang = source.get("lang")
        source_langs = source.get("langs", [source_lang])
        if translate_enabled and source_lang:
            for target in targets:
                if source_langs != [target] and section(text, f"== Translation {target}") is None:
                    enqueue("translations", audio + "\n" + target,
                            {**job, "target": target, "source_lang": source_lang,
                             "source_langs": source_langs})
    # The scheduled run stays open until a sweep finds nothing new and nothing
    # queued or running: translations only appear after their transcripts
    # finish, so closing after the first sweep would push them to tomorrow.
    if scheduled and created == 0 and not _has_pending_jobs(vault):
        state["last_scheduled_date"] = today
    return created


def run_once(vault, model=None, translate=None, *, now=None, state_path=None,
             hostname=None, clock=None, probe=None):
    vault = Path(vault).resolve()
    clock = clock or (lambda: datetime.now(timezone.utc))
    supplied_now = now
    now = now if now is not None else clock()
    settings = load_ai_settings(vault)
    model = resolve_whisper_model(settings, model)
    if translate is None:
        def translate(texts, source_lang, target, source_langs):
            identifier = settings.get("tasks", {}).get("translate", {}).get("connection")
            connection = next((entry for entry in settings.get("connections", [])
                               if entry["id"] == identifier), None)
            _, key = connection_credentials(connection)
            try:
                result = globals()["translate"](texts, source_lang, target, source_langs, settings=settings)
            except Exception as error:
                message = str(error).replace(key, "[redacted]") if key else str(error)
                raise ValueError(message) from None
            translate.last_model = globals()["translate"].last_model
            return result
    state_path = Path(state_path).expanduser() if state_path is not None else Path.home() / ".tylog-transcribe-state.json"
    state = _read_json(state_path)
    try:
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
                    segments, language, languages = transcribe(audio, model=model, lang=job.get("lang") or None)
                    updated_note = apply_transcript(note_text, segments)
                else:
                    updated_note = apply_translation(note_text, job["source_lang"], job["target"], translate,
                                                     job.get("source_langs", [job["source_lang"]]))
                with note.open("w", encoding="utf-8", newline="") as stream:
                    stream.write(updated_note)
                if kind == "transcripts":
                    job["lang"] = language
                    job["langs"] = languages
                elif getattr(translate, "last_model", None) is not None:
                    job["llm"] = translate.last_model
                job["status"] = "done"
                job["finished_at"] = datetime.now(timezone.utc).isoformat()
                job.pop("error", None)
            except Exception as error:
                job["status"] = "failed"
                job["error"] = str(error)
            job_path.write_text(json.dumps(job, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    finally:
        write_heartbeat(vault, settings, state, state_path,
                        supplied_now if supplied_now is not None else clock(),
                        hostname or socket.gethostname, probe or probe_connection)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--vault", required=True, type=Path)
    parser.add_argument("--once", required=True, action="store_true")
    parser.add_argument("--model", default=None)
    parser.add_argument("--state", type=Path, default=Path.home() / ".tylog-transcribe-state.json")
    args = parser.parse_args(argv)
    run_once(args.vault, model=args.model, state_path=args.state)


if __name__ == "__main__":
    main()
