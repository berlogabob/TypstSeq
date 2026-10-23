"""Extract entity mentions and keywords from daily notes into _system/enrich.

The worker never edits notes: it only writes mentions files, which the app
resolves against the vault and turns into links.
"""

import argparse
from datetime import datetime, timedelta, timezone
import gzip
import hashlib
import json
import os
from pathlib import Path
import re
import sys
import time
import unicodedata
from urllib.request import Request, urlopen

import transcribe_worker as tw


AUTO_MARKER = "// tylog:auto-entities"
ENTITY_KINDS = ("person", "organization", "place", "event", "website", "project")
MENTION_TYPES = ("person", "place", "organization", "project", "event", "topic")
SETTLE_SECONDS = 300


def strip_auto_block(text):
    index = text.find(AUTO_MARKER)
    return text if index < 0 else text[:index].rstrip("\n") + "\n"


def content_sha(text):
    """Hash of the user's text; the app writing its own block must not re-trigger.

    Trailing blanks are ignored: putting the block after the text normalizes
    them, and that must not look like an edit. Same as enrichContentSha (Dart).
    """
    index = text.find(AUTO_MARKER)
    body = text if index < 0 else text[:index]
    return hashlib.sha256((body.rstrip(" \t\r\n") + "\n").encode("utf-8")).hexdigest()


def body_lines(text):
    """(1-based line number, line) pairs of user-written text.

    Drops the header, headings, the auto block and generated `- Read:` lines
    (the `== Reading` section has no end marker; user text follows it).
    """
    lines = strip_auto_block(text).split("\n")
    kept, in_header = [], False
    for number, line in enumerate(lines, 1):
        stripped = line.strip()
        if stripped.startswith("#import"):
            continue
        if stripped.startswith("#show: tylog.note.with("):
            in_header = not stripped.endswith(")")
            continue
        if in_header:
            in_header = stripped != ")"
            continue
        if not stripped or stripped.startswith(("=", "- Read:")):
            continue
        kept.append((number, line))
    return kept


def read_index(vault):
    try:
        raw = (vault / "_index/index.json").read_bytes()
        return json.loads(gzip.decompress(raw) if raw[:2] == b"\x1f\x8b" else raw)
    except (OSError, ValueError):
        return {}


def known_entities(index, limit=200):
    # ponytail: sends every entity note up to `limit`; prefilter by token overlap with the note when vaults grow past it.
    return [{"id": note["id"], "title": note["title"], "kind": note["kind"],
             "aliases": note.get("aliases") or []}
            for note in index.get("notes", []) if note.get("kind") in ENTITY_KINDS][:limit]


def _fold(text):
    return "".join(c for c in unicodedata.normalize("NFKD", text.casefold())
                   if not unicodedata.combining(c))


def parse_reply(reply, lines):
    """Validate the model reply; drop mentions whose surface is not on that line."""
    reply = reply.strip()
    if reply.startswith("```"):
        reply = re.sub(r"^```[^\n]*\n", "", reply)
        reply = re.sub(r"\s*```$", "", reply)
    value = json.loads(reply)
    if not isinstance(value, dict):
        raise ValueError("Enrichment reply must be a JSON object")
    by_number = dict(lines)
    mentions = []
    for item in value.get("mentions") or []:
        if not isinstance(item, dict):
            continue
        surface, line = item.get("surface"), item.get("line")
        if not isinstance(surface, str) or not surface.strip() or not isinstance(line, int):
            continue
        if line not in by_number or _fold(surface) not in _fold(by_number[line]):
            continue  # hallucinated or mis-numbered
        kind = item.get("type") if item.get("type") in MENTION_TYPES else "topic"
        hints = [hint for hint in item.get("hints") or [] if isinstance(hint, str) and hint.strip()]
        mention = {"surface": surface.strip(), "type": kind, "line": line, "hints": hints[:5]}
        if isinstance(item.get("entity"), str) and item["entity"]:
            mention["entity"] = item["entity"]
        mentions.append(mention)
    keywords = [word.strip() for word in value.get("keywords") or []
                if isinstance(word, str) and word.strip()][:10]
    return mentions, keywords


SYSTEM_PROMPT = """You read one day of a personal journal and list what it mentions.
Return only a JSON object:
{"mentions": [{"surface": str, "type": "person|place|organization|project|event|topic",
  "line": int, "hints": [str], "entity": str?}], "keywords": [str]}
Rules:
- surface is copied exactly from that line (any language, keep the original script and case).
- line is the number shown before the text.
- hints: other forms the same name may take: full name, nickname or diminutive expansion,
  transliteration (e.g. "Катя" -> ["Екатерина", "Katya", "Katia"]). Never invent surnames.
- entity: the id from KNOWN ENTITIES only when the text makes it certain; otherwise omit.
- Only real named people, places, organizations, projects and events, plus at most a few
  topics the user clearly worked on. No pronouns, dates, times or generic nouns.
- keywords: up to 8 short topic words for the whole day, in the journal's language.
No commentary."""


def build_messages(lines, entities):
    numbered = "\n".join(f"{number}: {line}" for number, line in lines)
    known = json.dumps(entities, ensure_ascii=False)
    return [{"role": "system", "content": SYSTEM_PROMPT},
            {"role": "user", "content": f"KNOWN ENTITIES: {known}\n\nJOURNAL:\n{numbered}"}]


def load_task(vault):
    settings = tw._read_json(vault / "_system/settings/ai.json")
    tasks = settings.get("tasks") if isinstance(settings.get("tasks"), dict) else {}
    task = tasks.get("enrich") if isinstance(tasks.get("enrich"), dict) else {}
    connections = [entry for entry in settings.get("connections") or [] if isinstance(entry, dict)
                   and isinstance(entry.get("id"), str) and isinstance(entry.get("url"), str)]
    return task, connections


def make_chat(task, connections):
    """Chat over the task's connection, then its fallback_connection; OpenAI-compatible only."""
    order = [task.get("connection"), task.get("fallback_connection")]
    chosen = [next(c for c in connections if c["id"] == identifier)
              for identifier in order if identifier and any(c["id"] == identifier for c in connections)]
    if not chosen and not task.get("connection"):
        chosen = [None]  # legacy default: TYLOG_LLM_URL or the pi "studio" provider
    if not chosen:
        raise ValueError(f"Unknown enrich connection: {task.get('connection')}")

    def chat(messages):
        errors = []
        for connection in chosen:
            base, key = tw.connection_credentials(connection)
            if not base:
                errors.append("no url")
                continue
            headers = {"Content-Type": "application/json"}
            if key:
                headers["Authorization"] = f"Bearer {key}"
            try:
                model = os.environ.get("TYLOG_LLM_MODEL") or (
                    task.get("model") if connection is chosen[0] else task.get("fallback_model")
                ) or tw.probe_connection(base, key)["loaded"][0]
                payload = json.dumps({"model": model, "temperature": 0, "messages": messages}).encode("utf-8")
                with urlopen(Request(base.rstrip("/") + "/chat/completions", data=payload,
                                     headers=headers), timeout=900) as response:  # long days on a 35b model
                    reply = json.load(response)["choices"][0]["message"]["content"]
                return reply, model, connection["id"] if connection else "default"
            except Exception as error:
                message = str(error)
                errors.append(message.replace(key, "[redacted]") if key else message)
        raise ValueError("; ".join(errors))

    return chat


def due(task, state, now, force=False):
    mode = task.get("mode", "off")
    if force or mode in ("watch", "both"):
        return True
    when = task.get("time") or "03:00"
    if mode == "schedule":
        local = now.astimezone()
        return (re.fullmatch(r"(?:[01]\d|2[0-3]):[0-5]\d", when) is not None
                and local.strftime("%H:%M") >= when
                and state.get("last_scheduled_date") != local.date().isoformat())
    return False


def mentions_path(vault, note):
    return vault / "_system/enrich/mentions" / note.relative_to(vault).with_suffix(".json")


def run_once(vault, *, chat=None, now=None, state_path=None, limit=20, clock=time.time,
             since_days=90):
    vault = Path(vault).resolve()
    now = now or datetime.now(timezone.utc)
    state_path = Path(state_path or Path.home() / ".tylog-enrich-state.json")
    state = tw._read_json(state_path)
    task, connections = load_task(vault)
    requested = tw._read_json(vault / "_system/enrich/run-request.json").get("requested_at")
    force = bool(requested) and requested != state.get("last_run_request")
    if not due(task, state, now, force):
        return 0
    chat = chat or make_chat(task, connections)
    entities = known_entities(read_index(vault))
    failures = state.setdefault("failures", {})
    done = 0
    notes = sorted((vault / "daily").glob("*/*/*.typ"), reverse=True)  # newest day first
    # Older days only on "process now": a full backfill is ~80 s per note on a
    # 35b model, about a day of compute for a few years of journal.
    oldest = (now.astimezone().date() - timedelta(days=since_days)).isoformat()
    for note in notes:
        if done >= limit:
            break
        if not force and note.stem < oldest:
            break
        if clock() - note.stat().st_mtime < SETTLE_SECONDS:
            continue  # still being typed
        text = note.read_text(encoding="utf-8")
        sha = content_sha(text)
        target = mentions_path(vault, note)
        relative = note.relative_to(vault).as_posix()
        # A failure (server down, timeout) waits for the note to change or for
        # tomorrow: retrying every run would hammer a broken server.
        today = now.astimezone().date().isoformat()
        if tw._read_json(target).get("content_sha") == sha or failures.get(relative) == [sha, today]:
            continue
        lines = body_lines(text)
        try:
            if lines:
                reply, model, connection = chat(build_messages(lines, entities))
                mentions, keywords = parse_reply(reply, lines)
            else:
                mentions, keywords, model, connection = [], [], None, None
        except Exception as error:
            failures[relative] = [sha, today]
            print(f"enrich: {relative}: {error}", file=sys.stderr)
            done += 1
            continue
        failures.pop(relative, None)
        result = {"schema": 1, "note": relative, "content_sha": sha,
                  "extracted_at": now.astimezone(timezone.utc).isoformat(),
                  "model": model, "connection": connection,
                  "mentions": mentions, "keywords": keywords}
        target.parent.mkdir(parents=True, exist_ok=True)
        temporary = target.with_suffix(".json.tmp")
        temporary.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        temporary.replace(target)
        done += 1
    if force:
        state["last_run_request"] = requested
    if task.get("mode") == "schedule" and done < limit:
        state["last_scheduled_date"] = now.astimezone().date().isoformat()
    state_path.parent.mkdir(parents=True, exist_ok=True)
    state_path.write_text(json.dumps(state, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return done


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--vault", required=True, type=Path)
    parser.add_argument("--once", required=True, action="store_true")
    parser.add_argument("--limit", type=int, default=20, help="Notes per run (bounds backfill cost)")
    parser.add_argument("--since-days", type=int, default=90,
                        help="Days covered without a process-now request")
    parser.add_argument("--state", type=Path, default=Path.home() / ".tylog-enrich-state.json")
    args = parser.parse_args(argv)
    run_once(args.vault, state_path=args.state, limit=args.limit, since_days=args.since_days)


if __name__ == "__main__":
    main()
