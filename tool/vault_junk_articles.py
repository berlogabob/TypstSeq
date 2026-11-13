#!/usr/bin/env python3
"""Find and safely remove junk article notes from a Typst vault."""
from __future__ import annotations
import argparse, datetime as dt, json, os, re, shutil, sys
from pathlib import Path
from urllib.parse import urlsplit

sys.path.insert(0, str(Path(__file__).resolve().parent))
import vault_dedupe as vd
import vault_filenames as vf
from vault_article_titles import SUMMARY_JUNK, host_names

PIPELINE_SRC = Path(os.environ.get("PIPELINE_SRC", "~/Nextcloud/scripts/article-pipeline/src")).expanduser()
JUNK_LEDGER = Path(os.environ.get("JUNK_LEDGER", "~/Nextcloud/scripts/article-pipeline/junk_urls.jsonl")).expanduser()
SHELL = ("prove your humanity", "sign in to your account", "just a moment", "attention required", "access denied", "verifying", "redirecting")
REF = re.compile(r'#tylog\.ref-note\("((?:\\.|[^"\\])*)"\)')


def _pipeline():
    sys.path.insert(0, str(PIPELINE_SRC))
    junk_reason = is_generic_title = normalize_url = None
    errors = []
    try:
        from article_pipeline.processor import junk_reason
    except Exception as exc:
        errors.append(f"junk_reason skipped: {exc}")
    try:
        from article_pipeline.titles import is_generic_title
    except Exception as exc:
        errors.append(f"generic-title check skipped: {exc}")
    try:
        from article_pipeline.net import normalize_url
    except Exception as exc:
        errors.append(f"pipeline URL normalization unavailable: {exc}")
    return junk_reason, is_generic_title, normalize_url, "; ".join(errors) or None


def host_of(note):
    return (urlsplit(note["properties"].get("url") or "").hostname or "").removeprefix("www.")


def summary(body):
    m = re.search(r"(?m)^== Summary\s*$", body)
    if not m: return ""
    tail = body[m.end():]
    nxt = re.search(r"(?m)^==+\s+", tail)
    return tail[:nxt.start()] if nxt else tail


def extracted_body(body):
    lines = body.splitlines(); start = next((i + 1 for i, x in enumerate(lines) if x.strip().startswith("#line(length: 100%)")), None)
    if start is None: return ""
    end = next((i for i in range(start, len(lines)) if lines[i].strip() == "// tylog:auto-related"), len(lines))
    return "\n".join(lines[start:end]).strip()


def detect(note, funcs):
    junk_reason, is_generic_title, _, _ = funcs
    title, body, url = note["title"], note["body"], note["properties"].get("url", "")
    reasons=[]
    if junk_reason:
        try:
            reason=junk_reason(title, url)
            if reason: reasons.append(f"pipeline: {reason}")
        except Exception as exc: reasons.append(f"pipeline check failed: {exc}")
    host=host_of(note); summ=summary(body); extracted=extracted_body(body)
    if is_generic_title:
        try: generic=bool(is_generic_title(title, host, host_names(host)))
        except Exception: generic=False
        if generic and SUMMARY_JUNK.search(summ): reasons.append("generic title with junk summary")
    low=title.casefold(); body_lines=[x.strip().casefold() for x in body.splitlines() if x.strip() and not x.startswith("= ")]; first=body_lines[0] if body_lines else ""
    if any(s in low for s in SHELL): reasons.append("shell/error title")
    wall_words=("consent", "accept", "preferences", "согласи")
    if ("cookie" in low and any(w in low for w in wall_words)) or ("cookie" in first and any(w in first for w in wall_words)):
        reasons.append("cookie/consent wall")
    if host.casefold()=="habr.com" and (title.strip()=="Хабр" or re.search(r"(?i)(?:403|404|moderator.{0,30}remov|remov.{0,30}moderator|снят.{0,20}модератор)", summ)):
        reasons.append("Habr error or moderator removal")
    if len(extracted)<200 and (not summ.strip() or SUMMARY_JUNK.search(summ)):
        reasons.append("empty extracted body")
    return list(dict.fromkeys(reasons))


def _ignored(rel): return any(p.startswith(("_", ".")) for p in Path(rel).parts)


def inbound(vault, note):
    nid=note.get("id") or ""; rel=note["path"].relative_to(vault).as_posix(); hits=[]
    for p in Path(vault).rglob("*.typ"):
        r=p.relative_to(vault).as_posix()
        if _ignored(r): continue
        try: lines=p.read_text(encoding="utf-8").splitlines()
        except (OSError, UnicodeError): continue
        # Digest notes are generated source lists, not user-authored inbound links.
        try: parsed=vd.parse_note(p)
        except (OSError, UnicodeError, ValueError): parsed={}
        if str(parsed.get("id") or "").startswith("digest-"): continue
        related=False
        for line in lines:
            if line.strip()=="// tylog:auto-related": related=True; continue
            if related: continue
            if nid and any(m.group(1)==nid for m in REF.finditer(line)): hits.append(f"body link: {r}")
            if f'#include "/{rel}"' in line or f'#include "{rel}"' in line: hits.append(f"include: {r}")
    for root in (Path(vault)/"boards", Path(vault)/"_system/decisions"):
        if root.exists():
            for p in root.rglob("*.json"):
                try: text=p.read_text(encoding="utf-8")
                except (OSError, UnicodeError): continue
                if (nid and nid in text) or rel in text: hits.append(f"state reference: {p.relative_to(vault).as_posix()}")
    return list(dict.fromkeys(hits))


def collect(vault, ledger=None):
    vault=Path(vault); funcs=_pipeline(); rows=[]
    for n in vd.iter_notes(vault):
        if n.get("error") or n.get("kind")!="article": continue
        reasons=detect(n,funcs)
        if not reasons: continue
        props=n["properties"]; status=props.get("status"); sig=vd._user_signal(n); refs=inbound(vault,n)
        blockers=[]
        if status not in (None,"","unread","processed"): blockers.append(f"status={status}")
        if "rating" in props: blockers.append("has rating")
        if sig: blockers.append("user edits/signal")
        blockers.extend(refs)
        rows.append({"path":n["path"].relative_to(vault).as_posix(),"id":n.get("id"),"url":props.get("url",""),"reason":"; ".join(reasons),"status":status or "absent","rating":props.get("rating"),"user_signal":sig,"inbound_link_count":len(refs),"eligible":not blockers,"ineligible_reasons":blockers,"_note":n})
    return rows, funcs[3]


def _related_edit(text, nid):
    lines=text.splitlines(keepends=True); output=[]; related=False; changed=False
    pattern=re.compile(r'^\s*- #tylog\.ref-note\("'+re.escape(nid)+r'"\)\[[^\]]*\].*(?:\r?\n)?$')
    for line in lines:
        if line.strip()=="// tylog:auto-related": related=True
        if related and pattern.match(line): changed=True; continue
        output.append(line)
    return "".join(output),changed


def _digest_edit(text, nid):
    lines=text.splitlines(keepends=True); output=[]; changed=False
    pattern=re.compile(r'^\s*- #tylog\.ref-note\("'+re.escape(nid)+r'"\).*(?:\r?\n)?$')
    for line in lines:
        if pattern.match(line): changed=True; continue
        output.append(line)
    return "".join(output),changed


def _ledger_add(path, rows, normalize):
    path=Path(path); existing=set()
    if path.exists():
        for line in path.read_text(encoding="utf-8").splitlines():
            try: existing.add(json.loads(line).get("normalized"))
            except ValueError: pass
    additions=[]
    for row in rows:
        url=row["url"]
        if not url: continue
        norm=normalize(url) if normalize else vd.normalize_url(url)
        if norm in existing: continue
        obj={"ts":dt.datetime.now(dt.timezone.utc).isoformat(),"url":url,"normalized":norm,"reason":row["reason"],"note_id":row["id"],"source":"vault_junk_articles"}
        additions.append(json.dumps(obj,ensure_ascii=False,separators=(",",":"))); existing.add(norm)
    if additions:
        path.parent.mkdir(parents=True,exist_ok=True)
        with path.open("a",encoding="utf-8",newline="") as f:
            for line in additions: f.write(line+"\n")
    return additions


def apply(vault, rows, backup, manifest, ledger):
    vault=Path(vault); backup=Path(backup); vf.require_app_closed()
    selected=[r for r in rows if r["eligible"]]; funcs=_pipeline(); normalize=funcs[2]
    ledger=Path(ledger)
    doc={"version":1,"vault":str(vault),"backup":str(backup),"renames":[],"ref_edits":[],"ref_moves":[],"creates":[],"asset_moves":[],"ledger":str(ledger),"ledger_existed":ledger.exists(),"ledger_lines":[]}
    for row in selected:
        n=row["_note"]; rel=row["path"]
        vd.backup_file(vault,rel,backup); doc["ref_edits"].append({"file":rel,"backup":rel})
        # Existing Related list entries are removed from other notes and backed up byte-for-byte.
        for other in vd.iter_notes(vault):
            if other.get("error") or other.get("id")==n.get("id"): continue
            if str(other.get("id") or "").startswith("digest-"):
                updated,changed=_digest_edit(other["text"],n.get("id") or "")
            else:
                updated,changed=_related_edit(other["text"],n.get("id") or "")
            if changed:
                orel=other["path"].relative_to(vault).as_posix()
                if not any(x["file"]==orel for x in doc["ref_edits"]):
                    vd.backup_file(vault,orel,backup); doc["ref_edits"].append({"file":orel,"backup":orel})
                vd.atomic_write(other["path"],updated)
        n["path"].unlink()
        asset=Path(vault)/"assets/articles"/str(n.get("id") or "")
        if asset.is_dir():
            dest=backup/"assets/articles"/str(n.get("id") or ""); dest.parent.mkdir(parents=True,exist_ok=True)
            shutil.copytree(asset,dest); shutil.rmtree(asset)
            doc["asset_moves"].append({"from_backup":dest.relative_to(backup).as_posix(),"to":asset.relative_to(vault).as_posix()})
    doc["ledger_lines"]=_ledger_add(ledger,selected,normalize)
    vf._write_manifest(manifest,doc)
    return doc


def main(argv=None):
    ap=argparse.ArgumentParser(); ap.add_argument("vault",nargs="?"); ap.add_argument("--ledger",default=str(JUNK_LEDGER)); ap.add_argument("--report-out"); ap.add_argument("--apply",action="store_true"); ap.add_argument("--backup"); ap.add_argument("--manifest"); ap.add_argument("--revert",nargs=2,metavar=("MANIFEST","VAULT"))
    a=ap.parse_args(argv)
    if a.revert:
        print(json.dumps(vf.revert(a.revert[0],a.revert[1],a.apply),indent=2)); return 0
    if not a.vault: ap.error("VAULT required")
    rows,warning=collect(a.vault,a.ledger)
    report={"dry_run":not a.apply,"pipeline_warning":warning,"articles":[{k:v for k,v in r.items() if k!="_note"} for r in rows],"eligible":sum(r["eligible"] for r in rows),"ineligible":sum(not r["eligible"] for r in rows)}
    print("path | url | reason | status | rating | user-signal | inbound-link count")
    for r in rows: print(f'{r["path"]} | {r["url"]} | {r["reason"]} | {r["status"]} | {r["rating"]} | {r["user_signal"]} | {r["inbound_link_count"]}')
    print(json.dumps({"eligible":report["eligible"],"ineligible":report["ineligible"],"ineligible_reasons":{r["path"]:r["ineligible_reasons"] for r in rows if not r["eligible"]},"pipeline_warning":warning},ensure_ascii=False,indent=2))
    if a.report_out: Path(a.report_out).write_text(json.dumps(report,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
    if a.apply:
        if not a.backup or not a.manifest: ap.error("--apply requires --backup and --manifest")
        apply(a.vault,rows,a.backup,a.manifest,a.ledger)
    return 0
if __name__=="__main__": raise SystemExit(main())
