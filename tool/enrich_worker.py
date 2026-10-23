"""Extract entity mentions and keywords from daily notes into _system/enrich.

The worker never edits notes: it only writes mentions files, which the app
resolves against the vault and turns into links.
"""

import argparse
from collections import defaultdict
import fcntl
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
# Bump when the prompt or reply shape changes: older mentions files are
# re-read once so every day carries the same fields.
PROMPT_VERSION = 2


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


def _plain(line):
    """A journal line as the user reads it: no list marker, time or markup."""
    line = re.sub(r"#tylog\.[\w-]+\([^)]*\)(\[([^\]]*)\])?", r"\2", line)
    line = re.sub(r"^\s*(?:\\-|[-+*]|\d+\.)\s+", "", line)
    return re.sub(r"^\d{1,2}:\d{2}\s+", "", line).strip()


def load_markers(vault, task, index):
    """Marker pages from tasks.enrich.markers, each with up to 8 lines the user
    tagged with it (examples) and up to 4 they rejected (counter-examples).

    More tagged lines, better examples: this is how detection improves.
    """
    wanted = {name for name in task.get("markers") or [] if isinstance(name, str)}
    markers = [{"id": note["id"], "title": note["title"]} for note in index.get("notes", [])
               if wanted & {note["id"], note["title"], *(note.get("aliases") or [])}]
    if not markers:
        return []
    days = sorted((vault / "daily").glob("*/*/*.typ"), reverse=True)
    rejected = defaultdict(list)
    for ledger in (vault / "_system/enrich/feedback").glob("*.jsonl"):
        for row in ledger.read_text(encoding="utf-8").splitlines():
            try:
                event = json.loads(row)
            except ValueError:
                continue
            if event.get("decision") == "reject" and str(event.get("entity", "")).startswith("marker:"):
                rejected[event["entity"][7:]].append(event.get("surface", ""))
    for marker in markers:
        # Linked by id or by title: both resolve to the page.
        needle = re.compile(r'#tylog\.ref-note\("(?:%s|%s)"\)(\[[^\]]*\])?'
                            % (re.escape(marker["id"]), re.escape(marker["title"])))
        examples = []
        for day in days:
            if len(examples) >= 8:
                break
            for line in day.read_text(encoding="utf-8").splitlines():
                # The marker itself is not part of the example.
                if needle.search(line) and (text := _plain(needle.sub("", line))):
                    examples.append(text[:200])
        marker["examples"] = examples[:8]
        marker["not"] = [text[:200] for text in rejected[marker["id"]][-4:]]
    return markers


def parse_reply(reply, lines, markers=()):
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
    ids = {marker["id"]: marker["title"] for marker in markers}
    marked = []
    for item in value.get("markers") or []:
        if not isinstance(item, dict) or item.get("marker") not in ids:
            continue
        line = item.get("line")
        if line not in by_number or any(f'ref-note("{name}")' in by_number[line]
                                        for name in (item["marker"], ids[item["marker"]])):
            continue  # unknown line, or already tagged by the user
        if {"line": line, "marker": item["marker"]} not in marked:
            marked.append({"line": line, "marker": item["marker"]})
    return mentions, keywords, marked


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


MAX_CHARS = 30000  # ~12k tokens of Cyrillic: fits the 64k context with room to answer


def build_messages(lines, entities, markers=()):
    # ponytail: long imported pages are cut at MAX_CHARS; chunk them if their
    # tails turn out to matter.
    numbered, size = [], 0
    for number, line in lines:
        size += len(line) + 8
        if size > MAX_CHARS:
            break
        numbered.append(f"{number}: {line}")
    numbered = "\n".join(numbered)
    known = json.dumps(entities, ensure_ascii=False)
    system = SYSTEM_PROMPT
    if markers:
        system += """
MARKERS: the user starts some lines with a marker page to file them (e.g. "fixit" for a
problem to fix). Also return "markers": [{"line": int, "marker": id}] for each line the
user would file under that marker, judging by the examples; skip lines that already
carry it, and lines like the counter-examples. Return [] when none fit."""
        guide = json.dumps([{"id": m["id"], "title": m["title"], "examples": m["examples"],
                             "counter_examples": m["not"]} for m in markers], ensure_ascii=False)
        known = f"{known}\n\nMARKERS: {guide}"
    return [{"role": "system", "content": system},
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
                    task.get("model") if connection is chosen[0] else task.get("fallback_model"))
                loaded = tw.probe_connection(base, key)["loaded"]
                if not model:
                    if not loaded:
                        raise ValueError("no model loaded")
                    model = loaded[0]
                elif model not in loaded:
                    # Another job swapped the server's model: load ours back
                    # (64k context) rather than answer with whatever is there.
                    def request(route, body=None):
                        url = route if route.startswith("http") else base.rstrip("/") + route
                        data = json.dumps(body).encode("utf-8") if body is not None else None
                        with urlopen(Request(url, data=data, headers=headers),
                                     timeout=900 if route.endswith("/load") else 60) as response:
                            return json.load(response)
                    tw.ensure_model(base, key, model, request)
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
             since_days=90, include_notes=False):
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
    index = read_index(vault)
    entities = known_entities(index)
    markers = load_markers(vault, task, index)
    failures = state.setdefault("failures", {})
    done = 0
    # Older days only on "process now": a full backfill is ~80 s per note on a
    # 35b model, about a day of compute for a few years of journal.
    oldest = (now.astimezone().date() - timedelta(days=since_days)).isoformat()
    notes = [note for note in sorted((vault / "daily").glob("*/*/*.typ"), reverse=True)
             if force or note.stem >= oldest]  # newest day first
    if include_notes:
        # Pages (Logseq imports included) after the journal. Articles and
        # screenshots are machine text about other people: never enriched.
        notes += sorted((vault / "notes").rglob("*.typ"))
    for note in notes:
        if done >= limit:
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
        previous = tw._read_json(target)
        if (previous.get("content_sha") == sha and previous.get("prompt") == PROMPT_VERSION) \
                or failures.get(relative) == [sha, today]:
            continue
        lines = body_lines(text)
        try:
            if lines:
                reply, model, connection = chat(build_messages(lines, entities, markers))
                mentions, keywords, marked = parse_reply(reply, lines, markers)
            else:
                mentions, keywords, marked, model, connection = [], [], [], None, None
        except Exception as error:
            failures[relative] = [sha, today]
            print(f"enrich: {relative}: {error}", file=sys.stderr)
            done += 1
            continue
        failures.pop(relative, None)
        result = {"schema": 1, "prompt": PROMPT_VERSION, "note": relative, "content_sha": sha,
                  "extracted_at": now.astimezone(timezone.utc).isoformat(),
                  "model": model, "connection": connection,
                  "mentions": mentions, "keywords": keywords, "markers": marked}
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
    parser.add_argument("--wait", action="store_true",
                        help="Wait for a running worker instead of exiting (manual backfill)")
    parser.add_argument("--include-notes", action="store_true",
                        help="Also read notes/ (pages, Logseq imports) after the journal")
    args = parser.parse_args(argv)
    # One worker per Mac: a manual backfill and the LaunchAgent would
    # otherwise pay the model twice for the same notes.
    with open(Path.home() / ".tylog-enrich.lock", "w") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | (0 if args.wait else fcntl.LOCK_NB))
        except BlockingIOError:
            return
        run_once(args.vault, state_path=args.state, limit=args.limit, since_days=args.since_days,
                 include_notes=args.include_notes)


if __name__ == "__main__":
    main()
