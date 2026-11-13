"""Temporary-vault tests for vault_dedupe."""
import hashlib
import datetime as dt
import json
import os
import sys
from pathlib import Path

import pytest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import vault_dedupe as vd  # noqa: E402


def note(ident, title="Title", kind="article", props=None, body=""):
    p = props or {}
    properties = ", ".join(f'"{k}": {json.dumps(v, ensure_ascii=False) if v is not None else "none"}' for k, v in p.items())
    return ('#import "/_system/tylog.typ" as tylog\n\n#show: tylog.note.with(\n'
            f'  id: "{ident}",\n  title: {json.dumps(title, ensure_ascii=False)},\n  kind: "{kind}",\n'
            '  tags: (),\n  aliases: (),\n  project: none,\n'
            f'  properties: ({properties}{"," if properties else ":"}),\n)\n'
            f'\n= {title}\n== Summary\nsummary\n== Verification\nverified\n#line(length: 100%)\n{body}')


def put(root, rel, text):
    p = root / rel; p.parent.mkdir(parents=True, exist_ok=True); p.write_text(text, encoding="utf-8"); return p


@pytest.mark.parametrize("url,expected", [
    ("https://www.Example.com/a/?utm_source=x&x=1#frag", "https://example.com/a?x=1"),
    ("https://x.test/a/#/route", "https://x.test/a#/route"),
    ("https://x.test/a/#!route", "https://x.test/a#!route"),
    ("https://youtube.com/watch?si=abc&v=xyz&list=pl", "https://youtube.com/watch?v=xyz"),
    ("https://youtube.com/watch?list=pl&feature=share", "https://youtube.com/watch?list=pl"),
    ("https://youtu.be/xyz?si=junk", "https://youtu.be/watch?v=xyz"),
])
def test_normalize_url(url, expected):
    assert vd.normalize_url(url) == expected


def test_articles_dryrun_and_apply(tmp_path, monkeypatch):
    monkeypatch.setenv("VAULT_DEDUPE_SKIP_APP_CHECK", "1")
    vault=tmp_path/"vault"; vault.mkdir(); backup=tmp_path/"backup"; manifest=tmp_path/"manifest.json"
    put(vault,"a.typ",note("a",props={"url":"https://www.site.test/post/","status":"unread"},body="short\n"))
    put(vault,"b.typ",note("b",props={"url":"https://site.test/post","status":"unread"},body="longer body text\n"))
    put(vault,"c.typ",note("c",kind="note",body='- #tylog.ref-note("a")[A]\n- #tylog.ref-note("b")[B]\n- #tylog.ref-note("b")[Again]\n'))
    before={p.relative_to(vault).as_posix():p.read_bytes() for p in vault.rglob("*.typ")}
    d=vd.articles(vault,backup,manifest); assert d["dry_run"] and all((vault/k).read_bytes()==v for k,v in before.items())
    vd.articles(vault,backup,manifest,True)
    assert not (vault/"a.typ").exists() and (vault/"b.typ").exists()
    assert (backup/"a.typ").exists() and (backup/"a.typ").read_bytes()==before["a.typ"]
    text=(vault/"c.typ").read_text(); assert text.count('ref-note("b")')==2 and 'ref-note("a")' not in text


def test_user_signal_and_different_url(tmp_path, monkeypatch):
    monkeypatch.setenv("VAULT_DEDUPE_SKIP_APP_CHECK", "1")
    vault=tmp_path/"v"; vault.mkdir()
    put(vault,"a.typ",note("a",props={"url":"https://x.test/same","status":"read","rating":"4"},body="a much longer user authored body with plenty of extra material to win the content length tie breaker decisively\n"))
    put(vault,"b.typ",note("b",props={"url":"https://x.test/same","status":"read","rating":"5"},body="\n// tylog:auto-related\n== Related\n- #tylog.ref-note(\"z\")[z]\nextra user text\n"))
    put(vault,"c.typ",note("c",props={"url":"https://x.test/other"}))
    d=vd.articles(vault,tmp_path/"bk",tmp_path/"m")
    assert d["totals"]["needs_review"]==1 and d["groups"][0]["needs_review"][0]["path"]=="b.typ"
    vd.articles(vault,tmp_path/"bk",tmp_path/"m",True)
    assert (vault/"b.typ").exists() and (vault/"c.typ").exists()


def test_merge_list_report_and_plan(tmp_path):
    vault=tmp_path/"vault"; vault.mkdir()
    put(vault,"project.typ",note("p","Café (2)","project",body="project body\n"))
    put(vault,"person.typ",note("same","Cafe","person",body="same\n"))
    put(vault,"empty.typ",note("empty","Cafe (3)","note",body="\n").split("= Cafe (3)\n",1)[0]+"= Cafe (3)\n")
    put(vault,"same-content.typ",note("identical","Cafe (4)","note",body="project body\n"))
    put(vault,"other.typ",note("same","Cafe","note",body="password: very-secret\nuseful merged text\n"))
    before={p.relative_to(vault).as_posix():hashlib.sha256(p.read_bytes()).hexdigest() for p in vault.rglob("*.typ")}
    md=tmp_path/"list.md"; planfile=tmp_path/"plan.json"
    plan=vd.merge_list(vault,md,planfile)
    assert plan["groups"] and plan["groups"][0]["target"]["path"]=="project.typ"
    actions={x["action"] for g in plan["groups"] for x in g["steps"]}
    assert {"append","delete_empty","delete_identical"} <= actions
    text=md.read_text(); assert "[redacted]" in text and "Duplicated ids" in text
    assert before=={p.relative_to(vault).as_posix():hashlib.sha256(p.read_bytes()).hexdigest() for p in vault.rglob("*.typ")}
    assert json.loads(planfile.read_text())["version"]==1


def test_apply_plan_dryrun_sha_and_apply(tmp_path, monkeypatch):
    monkeypatch.setenv("VAULT_DEDUPE_SKIP_APP_CHECK", "1")
    vault=tmp_path/"v"; vault.mkdir()
    put(vault,"target.typ",note("target","A","project",body="base\n"))
    put(vault,"source.typ",note("old","A","note",body="merged body\n"))
    put(vault,"rename.typ",note("dup","Other","note",body=""))
    plan={"version":1,"groups":[{"key":"a","target":{"path":"target.typ","id":"target","sha256":vd._sha(vault/"target.typ")},"steps":[{"action":"append","path":"source.typ","id":"old","sha256":vd._sha(vault/"source.typ"),"inbound":0}]}],"new_ids":[{"path":"rename.typ","old_id":"dup","new_id":"dup-2","sha256":vd._sha(vault/"rename.typ")} ]}
    pp=tmp_path/"p.json"; pp.write_text(json.dumps(plan)); mf=tmp_path/"mf"; backup=tmp_path/"backup"
    before=(vault/"target.typ").read_bytes(); vd.apply_plan(vault,pp,backup,mf); assert (vault/"target.typ").read_bytes()==before
    vd.apply_plan(vault,pp,backup,mf,True)
    assert not (vault/"source.typ").exists() and "Merged from A" in (vault/"target.typ").read_text()
    assert "id: \"dup-2\"" in (vault/"rename.typ").read_text() and (backup/"source.typ").exists()
    put(vault,"source2.typ",note("x","A","note"))
    plan["groups"][0]["steps"][0]["path"]="source2.typ"; plan["groups"][0]["steps"][0]["sha256"]="bad"
    pp.write_text(json.dumps(plan)); d=vd.apply_plan(vault,pp,backup,mf,True)
    assert d["actions"][0]["status"]=="skipped"


def test_junk_title_replaced_from_removed_duplicate(tmp_path, monkeypatch):
    monkeypatch.setenv("VAULT_DEDUPE_SKIP_APP_CHECK", "1")
    vault = tmp_path / "vault"; vault.mkdir()
    put(vault, "a.typ", note("a", "Ht0CmwK_jZk", props={"url": "https://www.youtube.com/watch?v=Ht0&si=x"}, body="long transcript text\n" * 5))
    put(vault, "b.typ", note("b", "A Real Title: Quotes", props={"url": "https://youtube.com/watch?v=Ht0"}, body="x\n"))
    vd.articles(vault, tmp_path / "bk", tmp_path / "m", True)
    text = (vault / "a.typ").read_text(encoding="utf-8")
    assert not (vault / "b.typ").exists()
    assert 'title: "A Real Title: Quotes"' in text and "\n= A Real Title: Quotes\n" in text
    assert (tmp_path / "bk" / "a.typ").exists()


def test_apply_plan_escapes_merged_title(tmp_path, monkeypatch):
    monkeypatch.setenv("VAULT_DEDUPE_SKIP_APP_CHECK", "1")
    vault = tmp_path / "v"; vault.mkdir()
    put(vault, "target.typ", note("target", "Target", "project"))
    put(vault, "source.typ", note("source", "Storyboarding]] in [[Blender", "note", body="merged\n"))
    plan = {"groups": [{"target": {"path": "target.typ", "id": "target"}, "steps": [{"action": "append", "path": "source.typ", "id": "source", "sha256": vd._sha(vault / "source.typ")}]}]}
    pp = tmp_path / "plan.json"; pp.write_text(json.dumps(plan))
    vd.apply_plan(vault, pp, tmp_path / "backup", tmp_path / "manifest", True)
    text = (vault / "target.typ").read_text()
    assert r"== Merged from Storyboarding\]\] in \[\[Blender (" + dt.date.today().isoformat() + ")" in text.splitlines()
