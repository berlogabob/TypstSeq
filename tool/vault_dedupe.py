#!/usr/bin/env python3
"""Plan and apply safe duplicate-note cleanup for Typst vaults."""
from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import unicodedata
from urllib.parse import parse_qsl, urlencode, urlsplit, urlunsplit

PIPELINE_KEYS = {"status", "processed", "url", "source", "source_url", "author", "import_format", "import_source_name", "import_sha256", "llm_provider", "llm_model", "extraction"}
ASSET_KINDS = {"screenshot", "audio"}  # captures bound to their own asset file: never merged
DROP_PARAMS = {"fbclid", "gclid", "si", "is", "pp", "app", "feature"}


def _unquote(s: str) -> str:
    return re.sub(r"\\(.)", r"\1", s)


def _escape_typst_markup(s: str) -> str:
    return "".join("\\" + char if char in r"[]#*_$@<>`~" else char for char in s)


def _field(header: str, key: str) -> str | None:
    m = re.search(rf'(?m)^\s*{re.escape(key)}:\s*"((?:\\.|[^"\\])*)"', header)
    return _unquote(m.group(1)) if m else None


def _property_values(header: str) -> dict[str, str | None]:
    m = re.search(r'(?m)^\s*properties:\s*\((.*)\)\s*,?\s*$', header)
    if not m:
        return {}
    raw = m.group(1)
    out = {}
    for p in re.finditer(r'"((?:\\.|[^"\\])*)"\s*:\s*("((?:\\.|[^"\\])*)"|none)', raw):
        out[_unquote(p.group(1))] = _unquote(p.group(3)) if p.group(3) is not None else None
    return out


def parse_note(path: str | Path, text: str | None = None) -> dict:
    path = Path(path)
    if text is None:
        text = path.read_text(encoding="utf-8")
    lines = text.splitlines(keepends=True)
    start = next((i for i, line in enumerate(lines) if line.rstrip("\r\n") == "#show: tylog.note.with("), None)
    if start is None:
        raise ValueError("missing note header")
    end = next((i for i in range(start + 1, len(lines)) if lines[i].rstrip("\r\n") == ")"), None)
    if end is None:
        raise ValueError("unterminated note header")
    header = "".join(lines[start:end + 1])
    body = "".join(lines[end + 1:])
    return {"path": path, "id": _field(header, "id"), "title": _field(header, "title") or "", "kind": _field(header, "kind") or "note", "properties": _property_values(header), "header": header, "body": body, "text": text, "header_end": sum(map(len, lines[:end + 1]))}


def iter_notes(vault: str | Path):
    vault = Path(vault)
    for path in sorted(vault.rglob("*.typ")):
        rel = path.relative_to(vault)
        if any(p.startswith(("_", ".")) for p in rel.parts):
            continue
        try:
            yield parse_note(path)
        except (OSError, UnicodeError, ValueError) as exc:
            yield {"path": path, "error": str(exc)}


def fold_title(title: str) -> str:
    s = unicodedata.normalize("NFKD", title)
    return "".join(c for c in s if not unicodedata.combining(c) and c.isalnum()).casefold()


def strip_suffix(title: str) -> str:
    return re.sub(r"\s*-?\s*\(\d+\)$", "", title)


def atomic_write(path: str | Path, text: str) -> None:
    path = Path(path); mode = path.stat().st_mode
    fd, tmp = tempfile.mkstemp(dir=path.parent, prefix=f".{path.name}.")
    try:
        with os.fdopen(fd, "w", encoding="utf-8", newline="") as f:
            f.write(text)
        os.chmod(tmp, mode)
        os.replace(tmp, path)
    finally:
        if os.path.exists(tmp): os.unlink(tmp)


def backup_file(vault: str | Path, rel: str | Path, backup_dir: str | Path) -> Path:
    src = Path(vault) / rel; dst = Path(backup_dir) / rel
    dst.parent.mkdir(parents=True, exist_ok=True)
    if not dst.exists(): shutil.copy2(src, dst)
    return dst


def require_app_closed() -> None:
    if os.environ.get("VAULT_DEDUPE_SKIP_APP_CHECK") == "1": return
    try: p = subprocess.run(["pgrep", "-x", "TyLog"], text=True, capture_output=True)
    except OSError as e: raise RuntimeError(f"cannot check TyLog process: {e}")
    if p.stdout.strip(): raise RuntimeError("TyLog is running; close it before applying")


def repoint_links(vault: str | Path, mapping: dict[str, str], own_ids: dict[str, str] | None = None, write: bool = True) -> dict[str, int]:
    vault = Path(vault); own_ids = own_ids or {}; counts = {}
    if not mapping: return counts
    pat = re.compile(r'#tylog\.ref-note\("((?:\\.|[^"\\])*)"\)')
    item = re.compile(r'^- #tylog\.ref-note\("((?:\\.|[^"\\])*)"\)\[[^\]]*\]\s*$')
    for path in sorted(vault.rglob("*.typ")):
        rel = path.relative_to(vault)
        if any(p.startswith(("_", ".")) for p in rel.parts): continue
        try: text = path.read_text(encoding="utf-8")
        except (OSError, UnicodeError): continue
        if 'ref-note("' not in text or not any('ref-note("' + k + '")' in text for k in mapping): continue
        rel = rel.as_posix(); changed = 0; result = []
        lines = text.splitlines(keepends=True)
        items = [item.match(l.rstrip("\r\n")) for l in lines]
        i = 0
        while i < len(lines):
            if not items[i]:
                def sub(x):
                    nonlocal changed
                    if x.group(1) in mapping: changed += 1; return x.group(0).replace(x.group(1), mapping[x.group(1)])
                    return x.group(0)
                result.append(pat.sub(sub, lines[i])); i += 1; continue
            j = i
            while j < len(lines) and items[j]: j += 1
            have = {items[k].group(1) for k in range(i, j) if items[k].group(1) not in mapping}
            for k in range(i, j):
                old = items[k].group(1)
                if old not in mapping: result.append(lines[k]); continue
                new = mapping[old]; changed += 1
                if new == own_ids.get(rel) or new in have: continue
                have.add(new); result.append(lines[k].replace('ref-note("' + old + '")', 'ref-note("' + new + '")', 1))
            i = j
        if changed:
            if write: atomic_write(path, "".join(result))
            counts[rel] = changed
    return counts


def normalize_url(url: str) -> str:
    s=urlsplit(url.strip()); host=(s.hostname or "").lower()
    if host.startswith("www."): host=host[4:]
    path=s.path.rstrip("/")
    q=parse_qsl(s.query, keep_blank_values=True)
    yt=host in {"youtube.com", "m.youtube.com", "youtu.be", "music.youtube.com"}
    if yt:
        v=next((v for k,v in q if k=="v"), None); li=next((v for k,v in q if k=="list"), None)
        if host=="youtu.be" and path.strip("/") and v is None: v=path.strip("/")
        q=[("v",v)] if v is not None else ([('list',li)] if li is not None else [])
        if v is not None: path="/watch"
    else: q=[(k,v) for k,v in q if not k.lower().startswith("utm_") and k.lower() not in DROP_PARAMS]
    frag=s.fragment if s.fragment.startswith(("/", "!")) else ""
    return urlunsplit((s.scheme.lower(),host + ((":"+str(s.port)) if s.port else ""),path,urlencode(q),frag))


def _rel(vault, note): return note["path"].relative_to(vault).as_posix()
def _sha(path): return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def _generated_body(n):
    lines=n["body"].splitlines(keepends=True); kept=[]; related=False; generated=False; article=False
    for line in lines:
        if re.match(r"^= ", line): article=True; continue
        if article:
            if line.strip() == "// tylog:auto-related": related=True; article=False
            else: continue
        if line.strip()=="// tylog:auto-related": related=True; generated=True; continue
        if related:
            if line.startswith("== Related") or line.startswith("- #tylog.ref-note(") or not line.strip(): continue
            related=False
        if re.match(r"^= ",line) or re.match(r"^== (Summary|Verification)\s*$",line) or line.lstrip().startswith("#line("): continue
        kept.append(line)
    return "".join(kept)


def _user_signal(n):
    p=n["properties"]
    return p.get("status", "unread") != "unread" or bool(set(p)-PIPELINE_KEYS) or bool(_generated_body(n).strip()) or bool(re.search(r"(?im)^\s*- \[[ xX]\]|#tylog\.task",n["body"]))


def _job_refs(vault, removed):
    found=[]; root=Path(vault)/"_system/jobs"
    if root.exists():
        for p in root.rglob("*"):
            if p.is_file() and not p.name.endswith(".typ"):
                txt=p.read_text(encoding="utf-8",errors="ignore")
                for rel in removed:
                    if '"note_path": "'+rel+'"' in txt: found.append({"file":p.relative_to(vault).as_posix(),"note_path":rel})
    return found


def articles(vault, backup, manifest, apply=False):
    notes=[n for n in iter_notes(vault) if "error" not in n]; skipped=[_rel(vault,n)+": "+n["error"] for n in iter_notes(vault) if "error" in n]
    groups={}
    for n in notes:
        if n["kind"]=="article" and n["properties"].get("url"):
            groups.setdefault(normalize_url(n["properties"]["url"]),[]).append(n)
    output=[]; removed=[]; review=[]; fixes=[]
    for url, ns in sorted(groups.items()):
        if len(ns)<2: continue
        ns.sort(key=lambda n:(not _user_signal(n),-len(n["body"]),not bool(n["title"]),tuple(-ord(c) for c in (n["properties"].get("processed") or "")),_rel(vault,n)))
        keep=ns[0]; rem=[]; needs=[]
        for n in ns[1:]:
            if _user_signal(n): needs.append({"path":_rel(vault,n),"id":n["id"],"reason":"user signal"}); review.append(n)
            else: rem.append({"path":_rel(vault,n),"id":n["id"]}); removed.append(n)
        fixes.append((keep,[n for n in ns[1:] if not _user_signal(n)])); output.append({"url":url,"kept":{"path":_rel(vault,keep),"id":keep["id"]},"removed":rem,"needs_review":needs})
    mapping={n["id"]: next(g["kept"]["id"] for g in output if any(x["path"]==_rel(vault,n) for x in g["removed"])) for n in removed if n["id"]}
    own={_rel(vault,n):n["id"] for n in notes if n.get("id")}
    gone={_rel(vault,n) for n in removed}
    counts={}; titlefix=[]
    if apply:
        require_app_closed()
        for n in removed: backup_file(vault,_rel(vault,n),backup)
        affected=repoint_links(vault,mapping,own,write=False)
        for rel in affected:
            if rel not in gone: backup_file(vault,rel,backup)
        counts=repoint_links(vault,mapping,own)
        for k,rs in fixes:
            donor=next((r for r in rs if len(r["title"].split())>1),None)
            if len(k["title"].split())!=1 or not donor or k["title"].strip()=="" : continue
            fresh=parse_note(k["path"]); rawt=lambda h:re.search(r'(?m)^\s*title:\s*"((?:\\.|[^"\\])*)"',h)
            old,new=rawt(fresh["header"]),rawt(donor["header"])
            if not old or not new: continue
            head=lambda n:next((l for l in n["body"].splitlines() if l.startswith("= ")),None)
            oh,nh=head(fresh),head(donor)
            backup_file(vault,_rel(vault,k),backup)
            h=fresh["header"][:old.start(1)]+new.group(1)+fresh["header"][old.end(1):]
            body=fresh["body"]
            if oh and nh and _unquote(oh[2:]).replace("\\","")==fresh["title"].replace("\\",""): body=body.replace(oh,nh,1)
            atomic_write(k["path"],fresh["text"][:fresh["header_end"]-len(fresh["header"])]+h+body)
            titlefix.append({"path":_rel(vault,k),"old":fresh["title"],"new":donor["title"]})
        for n in removed: Path(n["path"]).unlink(missing_ok=True)
    else:
        counts=repoint_links(vault,mapping,own,write=False)
    counts={k:v for k,v in counts.items() if k not in gone}
    rm_paths=[x["path"] for g in output for x in g["removed"]]
    doc={"dry_run":not apply,"groups":output,"links_repointed":counts,"title_fixed":titlefix,"totals":{"duplicate_groups":len(output),"removed":len(removed),"kept":len(output),"needs_review":sum(len(g["needs_review"]) for g in output),"links_repointed":sum(counts.values()),"files_modified":len(counts)},"skipped_unparsable":skipped,"job_refs_dangling":_job_refs(vault,rm_paths)}
    Path(manifest).write_text(json.dumps(doc,indent=2,ensure_ascii=False)+"\n",encoding="utf-8")
    print(json.dumps(doc["totals"],indent=2)); return doc


def _body(n):
    lines=n["body"].splitlines(); out=[]; related=False; started=not any(l.startswith("= ") for l in lines)
    for line in lines:
        if re.match(r"^= ",line): started=True; continue
        if not started: continue
        if line.strip()=="// tylog:auto-related": related=True; continue
        if related:
            if line.startswith("== Related") or line.startswith("- #tylog.ref-note(") or not line.strip(): continue
            related=False
        if re.match(r"^== (Summary|Verification)\s*$",line) or line.lstrip().startswith("#line("): continue
        out.append(line)
    return "\n".join(out).strip()
def _normbody(n): return " ".join(_body(n).split())


def merge_list(vault, out_md, out_json):
    ns=[n for n in iter_notes(vault) if "error" not in n]; bad=[_rel(vault,n) for n in iter_notes(vault) if "error" in n]; parent=list(range(len(ns)))
    def find(x):
        while parent[x]!=x: parent[x]=parent[parent[x]]; x=parent[x]
        return x
    def join(a,b): parent[find(a)]=find(b)
    keys=[fold_title(strip_suffix(n["title"])) for n in ns]; stems=[fold_title(strip_suffix(n["path"].stem)) for n in ns]
    for i in range(len(ns)):
        for j in range(i):
            if keys[i]==keys[j] or stems[i]==keys[j] or keys[i]==stems[j]: join(i,j)
    clusters={}
    for i,n in enumerate(ns): clusters.setdefault(find(i),[]).append(n)
    inbound={}; title_refs={}; ids={n["id"] for n in ns if n["id"]}; titles={n["title"] for n in ns if n["title"]}
    refpat=re.compile(r'#tylog\.ref-note\("((?:\\.|[^"\\])*)"\)')
    for src in ns:
        for m in refpat.finditer(src["text"]):
            r=m.group(1)
            if r in ids and r!=src["id"]: inbound[r]=inbound.get(r,0)+1
            elif r in titles: title_refs[r]=title_refs.get(r,0)+1
    rank={"project":0,"person":1,"place":2,"organization":3,"note":4}; groups=[]
    idsets={}
    for n in ns:
        if n["id"]: idsets.setdefault(n["id"],[]).append(n)
    work=[(m,False) for m in clusters.values()]
    covered=[{id(n) for n in m if n["kind"] not in ASSET_KINDS} for m,_ in work if len([n for n in m if n["kind"] not in ASSET_KINDS])>=2 and not all(n["kind"]=="article" for n in m if n["kind"] not in ASSET_KINDS)]
    for same in idsets.values():
        # Same id + same folded title + same kind = one page stored twice (e.g. "(2)" copies): propose a merge even for articles.
        if len(same)>1 and len({fold_title(strip_suffix(n["title"])) for n in same})==1 and len({n["kind"] for n in same})==1 and len({n["properties"].get("url") for n in same})==1 and not any({id(n) for n in same}<=c for c in covered):
            work.append((same,True))
    def steps_for(target,members):
        steps=[]
        for n in members:
            if n is target: continue
            if _normbody(n)==_normbody(target): act="delete_identical"
            elif not _normbody(n): act="delete_empty"
            else: act="append"
            if act!="append" and (_user_signal(n) and n["properties"].get("status","unread")!="unread" or set(n["properties"])-PIPELINE_KEYS): act="append"  # keeps its header values as a comment
            steps.append({"action":act,"path":_rel(vault,n),"id":n["id"],"sha256":_sha(n["path"]),"inbound":inbound.get(n["id"],0)})
        return steps
    for members,by_id in work:
        members=[n for n in members if n["kind"] not in ASSET_KINDS]
        if len(members)<2 or (all(n["kind"]=="article" for n in members) and not by_id): continue
        target=min(members,key=lambda n:(rank.get(n["kind"],5),not (by_id and (_user_signal(n) and (n["properties"].get("status","unread")!="unread" or bool(set(n["properties"])-PIPELINE_KEYS)))),-inbound.get(n["id"],0),-len(_body(n)),_rel(vault,n)))
        groups.append({"key":keys[ns.index(members[0])],"target":{"path":_rel(vault,target),"id":target["id"],"sha256":_sha(target["path"])},"steps":steps_for(target,members),"_members":members,"_target":target})
    order={"append":0,"delete_empty":1,"delete_identical":2}
    groups.sort(key=lambda g:(0 if len({n["kind"] for n in g["_members"]})>1 and any(s["action"]=="append" for s in g["steps"]) else 1 if any(s["action"]=="append" for s in g["steps"]) else 2 if len({n["kind"] for n in g["_members"]})>1 else 3,g["key"]))
    idgroups={}
    for n in ns:
        if n["id"]: idgroups.setdefault(n["id"],[]).append(n)
    new_ids=[]
    for ident, same in idgroups.items():
        if len(same)>1 and not any(all(n in g["_members"] for n in same) for g in groups):
            winner=max(same,key=lambda n:(inbound.get(ident,0),len(_body(n))))
            for n in same:
                if n is not winner: new_ids.append({"path":_rel(vault,n),"old_id":ident,"new_id":ident+"-2","sha256":_sha(n["path"])})
    plan={"version":1,"created":dt.datetime.now(dt.timezone.utc).isoformat(),"groups":[{k:v for k,v in g.items() if not k.startswith("_")} for g in groups],"new_ids":new_ids}
    counts={a:sum(s["action"]==a for g in groups for s in g["steps"]) for a in order}
    md=[f"# Duplicate merge proposals\n\nActions: append {counts['append']}, delete_empty {counts['delete_empty']}, delete_identical {counts['delete_identical']}\n"]
    for g in groups:
        target=g["_target"]; md += [f"\n### {g['key']} [{', '.join(sorted({n['kind'] for n in g['_members']}))}]\n",f"target: {_rel(vault,target)} ({target['kind']}, body {len(_body(target))}, in {inbound.get(target['id'],0)})\n"]
        for step,n in zip(g["steps"],[n for n in g["_members"] if n is not target]):
            snippet=[]
            for line in _body(n).splitlines():
                if re.search(r"pswrd|password|passwd|secret|token|api key|apikey|login::",line,re.I): snippet.append("[redacted]")
                else: snippet.append(line)
            sn=" ".join(" ".join(snippet).split())[:120]
            md.append(f"- {step['action']}: {step['path']} ({n['kind']}, body {len(_body(n))}, in {step['inbound']}, {n['id']}) \"{sn}\"\n")
    md.append("\n## Duplicated ids\n")
    for ident,same in idgroups.items():
        if len(same)<2: continue
        mg=any(all(n in g["_members"] for n in same) for g in groups)
        proposal="same page: handled by merge group" if mg else f"keep id on {_rel(vault,max(same,key=lambda n:(inbound.get(ident,0),len(_body(n)))))}; give another page new id {ident}-2 (check uniqueness)"
        md.append(f"- {ident}: "+"; ".join(f"{_rel(vault,n)} ({n['kind']}, {n['title']}, in {inbound.get(ident,0)})" for n in same)+f"; proposal: {proposal}\n")
    md.append("\n## Unparsable files\n"+("\n".join("- "+x for x in bad) if bad else "- None")+"\n")
    Path(out_md).write_text("".join(md),encoding="utf-8"); Path(out_json).write_text(json.dumps(plan,indent=2,ensure_ascii=False)+"\n",encoding="utf-8")
    return plan


def apply_plan(vault, plan_file, backup, manifest, apply=False):
    plan=json.loads(Path(plan_file).read_text()); actions=[]; counts={}; kept=[]; removed=[]; mapping={}
    own_ids={n["path"].relative_to(vault).as_posix():n["id"] for n in iter_notes(vault) if "error" not in n and n.get("id")}
    if apply: require_app_closed()
    for group in plan.get("groups",[]):
        target=Path(vault)/group["target"]["path"]
        for step in group["steps"]:
            src=Path(vault)/step["path"]
            if step["path"]==group["target"]["path"] or not target.exists(): actions.append({"path":step["path"],"status":"skipped","reason":"source is target or target missing"}); continue
            if not src.exists() or _sha(src)!=step["sha256"]: actions.append({"path":step["path"],"status":"skipped","reason":"sha256 changed or source missing"}); continue
            actions.append({"path":step["path"],"action":step["action"],"status":"applied" if apply else "planned"}); removed.append(step["path"]); kept.append(group["target"]["path"])
            if not apply: continue
            backup_file(vault,group["target"]["path"],backup) if step["action"]=="append" else None
            backup_file(vault,step["path"],backup)
            if step["action"]=="append":
                srcnote=parse_note(src); targetnote=parse_note(target)
                date=dt.date.today().isoformat(); tags=re.search(r'(?m)^\s*tags:.*$',srcnote["header"]); aliases=re.search(r'(?m)^\s*aliases:.*$',srcnote["header"]); props=re.search(r'(?m)^\s*properties:.*$',srcnote["header"])
                extra=f"\n// merged from {step['path']} id {step['id']} tags {tags.group(0).strip() if tags else '()'} aliases {aliases.group(0).strip() if aliases else '()'} properties {props.group(0).strip() if props else '(:)'}\n== Merged from {_escape_typst_markup(srcnote['title'])} ({date})\n"+srcnote["body"]
                atomic_write(target,targetnote["text"]+extra)
            mapping[step["id"]]=group["target"]["id"]
            src.unlink()
    if apply and mapping:
        for k in list(mapping):
            seen={k}
            while mapping[k] in mapping and mapping[k] not in seen: seen.add(mapping[k]); mapping[k]=mapping[mapping[k]]
        for rel in repoint_links(vault,mapping,own_ids,write=False): backup_file(vault,rel,backup) if (Path(vault)/rel).exists() else None
        counts=repoint_links(vault,mapping,own_ids)
    for item in plan.get("new_ids",[]):
        p=Path(vault)/item["path"]
        if not p.exists() or _sha(p)!=item["sha256"]: actions.append({"path":item["path"],"status":"skipped","reason":"sha256 changed or file missing"}); continue
        actions.append({"path":item["path"],"action":"new_id","status":"applied" if apply else "planned"})
        if apply:
            backup_file(vault,item["path"],backup); n=parse_note(p); h=re.sub(r'(?m)^(\s*id:\s*)"(?:\\.|[^"\\])*"',lambda m:m.group(1)+json.dumps(item["new_id"]),n["header"],count=1); atomic_write(p,n["text"].replace(n["header"],h,1))
    doc={"dry_run":not apply,"actions":actions,"kept":sorted(set(kept)),"removed":removed,"links_repointed":counts}; Path(manifest).write_text(json.dumps(doc,indent=2)+"\n"); return doc


def main(argv=None):
    p=argparse.ArgumentParser(); sub=p.add_subparsers(dest="cmd",required=True)
    a=sub.add_parser("articles"); a.add_argument("vault"); a.add_argument("--backup",required=True); a.add_argument("--manifest",required=True); a.add_argument("--apply",action="store_true")
    m=sub.add_parser("merge-list"); m.add_argument("vault"); m.add_argument("--out-md",required=True); m.add_argument("--out-json",required=True)
    q=sub.add_parser("apply-plan"); q.add_argument("vault"); q.add_argument("--plan",required=True); q.add_argument("--backup",required=True); q.add_argument("--manifest",required=True); q.add_argument("--apply",action="store_true")
    x=p.parse_args(argv)
    try:
        if x.cmd=="articles": articles(x.vault,x.backup,x.manifest,x.apply)
        elif x.cmd=="merge-list": merge_list(x.vault,x.out_md,x.out_json)
        else: apply_plan(x.vault,x.plan,x.backup,x.manifest,x.apply)
    except RuntimeError as e: print(str(e),file=sys.stderr); return 2
    return 0

if __name__=="__main__": raise SystemExit(main())
