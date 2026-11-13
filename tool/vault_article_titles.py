#!/usr/bin/env python3
"""Improve article titles from offline note content, with optional model fallback."""
from __future__ import annotations
import argparse, json, os, re, sys
from pathlib import Path
from urllib.parse import urlsplit

sys.path.insert(0, str(Path(__file__).resolve().parent))
import vault_dedupe as vd
import vault_filenames as vf

PIPELINE_SRC = Path(os.environ.get("PIPELINE_SRC", "~/Nextcloud/scripts/article-pipeline/src")).expanduser()
sys.path.insert(0, str(PIPELINE_SRC))
from article_pipeline.titles import is_generic_title, strip_site_affixes, summary_title, normalise_title

SECTION_WORDS = {"summary", "verification", "guidance", "related", "введение", "оглавление"}
ESCAPE = set(r"\\#$*_`<>@[]~=-+/()")


def host_of(note):
    source = note["properties"].get("source")
    if source: return source
    url = note["properties"].get("url") or ""
    return (urlsplit(url).hostname or "").removeprefix("www.")


def host_names(host):
    return {host, host.removeprefix("www."), host.split(".")[0], host.removeprefix("www.").split(".")[0]} - {""}


def unescape(s): return re.sub(r"\\(.)", r"\1", s)
def escape_markup(s): return "".join("\\" + c if c in ESCAPE else c for c in s)
def serialise(s): return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def candidate_lines(body):
    lines = body.splitlines()
    start = next((i + 1 for i, x in enumerate(lines) if x.strip().startswith("#line(length: 100%)")), None)
    if start is None: return []
    content = lines[start:]
    nonempty = 0; out=[]; pending_title=False
    for line in content:
        if not line.strip(): continue
        nonempty += 1
        if nonempty > 5: break
        m = re.match(r"^={2,}\s+(.+?)\s*=*\s*$", line)
        if m: out.append(unescape(m.group(1))); continue
        m = re.match(r"^Title:\s*(.*)$", line, re.I)
        if m:
            if m.group(1).strip(): out.append(unescape(m.group(1).strip()))
            else: pending_title=True
            continue
        if pending_title: out.append(unescape(line.strip())); pending_title=False
    return out


HEADING_JUNK = {"accessibility links", "skip to content", "skip to main content", "table of contents", "contents", "menu", "navigation"}


def clean_heading(value):
    """Tidy a body heading into a title, or "" when it is not title material."""
    value = re.sub(r"^.{1,80}? on (?:X|Twitter|Threads)\s*[:\-]?\s*", "", value.strip(), flags=re.S) if re.search(r" on (?:X|Twitter|Threads)\b", value[:100]) else value.strip()
    value = re.sub(r"https?://\S+", "", value).strip(" \"'“”«»")
    value = " ".join(value.split())
    if len(value) > 80:
        value = value[:80].rsplit(" ", 1)[0].rstrip(" .,;:-–—")
    if re.match(r"^\d+[.)]\s", value) or "#" in value or re.search(r"[\U0001F000-\U0001FAFF\u2600-\u27BF]", value): return ""
    if value.casefold() in HEADING_JUNK or len(value) < 15 or len(value.split()) < 3: return ""
    return value


BOILERPLATE = re.compile(r"^(?:Это\s+)?(?:Материал|Статья|Публикация|Твит|Пост|Страница|Документ|Видео|Текст|Данный текст|Ссылка|Запись)(?:\s+с\s+аккаунта\s+\S+)?(?:\s+в\s+X)?\s+(?:кратко\s+)?(?:описывает|представляет(?:\s+собой)?|сообщает(?:\s+о)?|анонсирует|заявлен[а]?\s+как|содержит|рассказывает(?:\s+о)?|показывает|посвящ[её]н[а]?|обсуждает)\s+", re.I)
SUMMARY_JUNK = re.compile(r"(?i)не найден|бессвязн|страниц\w* (?:входа|авторизации)|oauth|проверк\w+ безопасности|заглушк|ошибк\w+ 40\d|ссылка на общую|возвращает ошибку|недоступн|страниц\w* проверк|captcha|человечност|человеческ\w+ фактор|невозможно определить|ошибк\w+ 40\d|проверк\w+ (?:на бота|подлинности|человека)|верификаци|снят\w* с публикации|скрыт|заблокирован|prove your humanity|страниц\w* аутентификации|только навигаци|подтверждени\w+ человеч")


def refine_summary_title(value):
    if SUMMARY_JUNK.search(value): return ""
    stripped = BOILERPLATE.sub("", value).strip(" .,;:")
    if len(stripped) >= 15: value = stripped[:1].upper() + stripped[1:]
    return value


def summary_text(body):
    m = re.search(r"(?m)^==\s+Summary\s*$", body)
    if not m: return ""
    tail = body[m.end():]
    next_section = re.search(r"(?m)^==+\s+", tail)
    text = tail[:next_section.start()] if next_section else tail
    return unescape(text).strip()


def line_locations(text):
    lines=text.splitlines(keepends=True)
    h=[i for i,x in enumerate(lines) if re.match(r'^\s*title:\s*"(?:\\.|[^"\\])*"\s*,\s*(?:\r?\n)?$',x)]
    return lines,h


def choose(note, host, shared, chat=None, model_budget=None):
    title=note["title"]; reason_generic=is_generic_title(title,host,host_names(host))
    if not reason_generic and not shared: return title,"unresolved"
    # A real title shared by mirrors/duplicates is correct as it is: never swap it
    # for a body heading or a summary excerpt.
    if shared and not reason_generic: return title,"kept-shared"
    for value in candidate_lines(note["body"]):
        if value.casefold().strip(" .") in SECTION_WORDS: continue
        value=clean_heading(strip_site_affixes(value,host_names(host),host))
        if not value or is_generic_title(value,host,host_names(host)): continue
        return value,"offline-heading"
    summary=summary_text(note["body"])
    if SUMMARY_JUNK.search(summary) or len(summary)<40: return title,"unresolved"
    if summary:
        value=refine_summary_title(summary_title(summary,80).strip())
        if len(value)>=12 and value.casefold()!=host.casefold() and not is_generic_title(value,host,host_names(host)):
            return value,"offline-summary"
    if chat is not None and model_budget is not None and model_budget[0]>0:
        model_budget[0]-=1
        model_budget[1]+=1
        try:
            reply,_,_=chat([{"role":"system","content":"Reply with one JSON object {\"title\": \"...\"}."},{"role":"user","content":f"Give a concise title (max 80 characters, same language as the text) for this article summary: {summary[:1200]}"}])
            value=normalise_title(json.loads(reply)["title"],80).strip()
            if len(value)>80: value=value[:80].rsplit(" ",1)[0]
            if value and not SUMMARY_JUNK.search(value) and not is_generic_title(value,host,host_names(host)): return value,"model"
        except Exception:
            pass
    return title,"unresolved"


def collect(vault, chat=None, max_model_calls=200, no_model=False):
    vault=Path(vault); notes=[]
    for p in sorted((vault/"articles").glob("*.typ")):
        try: n=vd.parse_note(p)
        except (OSError,ValueError,UnicodeError): continue
        if n["kind"]=="article": notes.append(n)
    groups={}
    for n in notes: groups.setdefault(vd.fold_title(n["title"]),[]).append(n)
    budget=[0 if no_model else max_model_calls,0]
    if chat is None and not no_model:
        try:
            import enrich_worker as ew
            task,connections=ew.load_task(vault); chat=ew.make_chat(task,connections)
        except Exception: chat=None
    rows=[]
    for n in notes:
        host=host_of(n); url=n["properties"].get("url")
        distinct=any(not url or not x["properties"].get("url") or vd.normalize_url(url)!=vd.normalize_url(x["properties"].get("url")) for x in groups[vd.fold_title(n["title"])] if x is not n)
        generic=bool(is_generic_title(n["title"],host,host_names(host)))
        shared=distinct and len(groups[vd.fold_title(n["title"])])>1
        new,method=choose(n,host,shared,chat,budget) if generic or shared else (n["title"],"unresolved")
        rel=n["path"].relative_to(vault).as_posix(); props=n["properties"]
        prefix=re.match(r"^([A-Za-z0-9][A-Za-z0-9.-]*\.[A-Za-z]{2,}) - ",n["path"].stem)
        filehost=prefix.group(1) if prefix else host
        stembase=n["path"].stem[len(prefix.group(0)):] if prefix else n["path"].stem
        desired=vf.clean_stem(f"{filehost} - {new}" if prefix else f"{host} - {new}") if new!=n["title"] else stembase
        rows.append({"file":rel,"title":n["title"],"new_title":new,"method":method,"host":host,"wanted_stem":desired,"rated_or_read":bool(props.get("rating") is not None or props.get("status","") not in {"unread","processed",""})})
    return rows,budget[1]


def _replacement(text, old, new):
    lines, matches=line_locations(text)
    if len(matches)!=1: raise ValueError("header title line not found exactly once")
    hi=matches[0]; header_idx=next((i for i,l in enumerate(lines) if l.rstrip("\r\n")==")"),None)
    heading=next((i for i in range((header_idx or 0)+1,len(lines)) if lines[i].startswith("= ")),None)
    if heading is None: raise ValueError("top-level heading missing")
    lines[hi]=re.sub(r'("(?:\\.|[^"\\])*")',serialise(new),lines[hi],count=1)
    lines[heading]="= "+escape_markup(new)+("\r\n" if lines[heading].endswith("\r\n") else "\n" if lines[heading].endswith("\n") else "")
    return "".join(lines)


def apply_plan(vault, rows, backup, manifest):
    vault=Path(vault); backup=Path(backup); vf.require_app_closed()
    doc={"version":1,"vault":str(vault),"backup":str(backup),"renames":[],"ref_edits":[],"ref_moves":[]}
    eligible={r["file"]:r for r in rows if r["new_title"]!=r["title"]}
    wanted={rel:r["wanted_stem"] for rel,r in eligible.items()}
    renames=vf.plan_targets(vault,wanted)
    byold={x["old"]:x for x in renames}
    for rel,r in eligible.items():
        p=vault/rel
        try:
            with p.open(encoding="utf-8", newline="") as f: raw=f.read()
            parsed=vd.parse_note(p,raw); updated=_replacement(raw,parsed["title"],r["new_title"])
            with p.open(encoding="utf-8", newline="") as f: current=f.read()
            if current!=raw: raise ValueError("file changed during apply")
            if rel not in {x["file"] for x in doc["ref_edits"]}:
                vd.backup_file(vault,rel,backup); doc["ref_edits"].append({"file":rel,"backup":rel})
            vd.atomic_write(p,updated)
            if rel in byold:
                item=byold[rel]; dst=vault/item["new"]; dst.parent.mkdir(parents=True,exist_ok=True); os.rename(p,dst)
                doc["renames"].append({"old":rel,"new":item["new"],"sha256":vf._sha(dst)})
        except Exception as exc: print(f"unresolved apply {rel}: {exc}",file=sys.stderr)
    vf.update_references(vault,doc["renames"],backup,doc)
    vf._write_manifest(manifest,doc)
    return doc


def main(argv=None):
    ap=argparse.ArgumentParser(); ap.add_argument("vault",nargs="?"); ap.add_argument("--apply",action="store_true"); ap.add_argument("--backup"); ap.add_argument("--manifest"); ap.add_argument("--plan-out"); ap.add_argument("--plan-in"); ap.add_argument("--max-model-calls",type=int,default=200); ap.add_argument("--no-model",action="store_true"); ap.add_argument("--revert",nargs=2,metavar=("MANIFEST","VAULT"))
    a=ap.parse_args(argv)
    if a.revert:
        print(json.dumps(vf.revert(a.revert[0],a.revert[1],a.apply),indent=2)); return 0
    if a.plan_in:
        doc=json.loads(Path(a.plan_in).read_text()); rows=doc["articles"]; calls=doc.get("model_calls_used",0)
    else:
        if not a.vault: ap.error("VAULT required")
        rows,calls=collect(a.vault,max_model_calls=a.max_model_calls,no_model=a.no_model)
    if not a.plan_in and a.vault:
        targets={r["file"]:r["wanted_stem"] for r in rows if r["new_title"]!=r["title"]}
        moves={x["old"]:x["new"] for x in vf.plan_targets(a.vault,targets)}
        for r in rows: r["new_file"]=moves.get(r["file"],r["file"])
    if a.plan_out: Path(a.plan_out).write_text(json.dumps({"articles":rows,"model_calls_used":calls},ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
    for r in rows: print(f'{r["title"]} -> {r["new_title"]}  [{r["method"]}]  file: {r["file"]} -> {r.get("new_file",r["file"])}')
    counts={k:sum(x["method"]==k for x in rows) for k in ("offline-heading","offline-summary","model","unresolved","kept-shared")}
    shared={}
    for r in rows: shared.setdefault(vd.fold_title(r["new_title"]),[]).append(r)
    print(json.dumps({**counts,"model_calls_used":calls,"planned_renames":sum(x["title"]!=x["new_title"] for x in rows),"remaining_shared_titles":sum(len(x)>1 for x in shared.values())},ensure_ascii=False))
    if a.apply:
        if not a.backup or not a.manifest: ap.error("--apply requires --backup and --manifest")
        apply_plan(a.vault,rows,a.backup,a.manifest)
    return 0
if __name__=="__main__": raise SystemExit(main())
