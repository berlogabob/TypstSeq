"""Temporary vault only tests; pipeline rules are isolated behind a fake module."""
import json, os, sys, types
from pathlib import Path
import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent))
rules=types.ModuleType("article_pipeline.titles")
rules.is_generic_title=lambda title,host,names=(): "generic" if title.casefold() in {host.casefold(),"untitled","article"} else None
rules.strip_site_affixes=lambda title,names,host: title.removesuffix(" | Example")
rules.summary_title=lambda summary,max_chars=80: summary.split(".",1)[0][:max_chars]
rules.normalise_title=lambda text,max_chars=200: " ".join(text.split())[:max_chars]
pkg=types.ModuleType("article_pipeline"); pkg.__path__=[]
sys.modules["article_pipeline"]=pkg; sys.modules["article_pipeline.titles"]=rules
import vault_article_titles as vat
import vault_dedupe as vd


def note(root, rel, title, url, body="", source=None):
    p=root/rel; p.parent.mkdir(parents=True,exist_ok=True)
    props=f'"url": "{url}",'+(f' "source": "{source}",' if source else '')+' "status": "unread"'
    with p.open('w',encoding='utf-8',newline='') as f: f.write(f'#show: tylog.note.with(\n  title: "{title}",\n  kind: "article",\n  properties: ({props}),\n)\n#line(length: 100%)\n= {title}\n{body}')
    return p


def test_offline_heading_summary_shared_and_model(tmp_path):
    v=tmp_path/'v'
    note(v,'articles/example.com - Example.com.typ','example.com','https://example.com/a',r'== A Deep Story About Fixtures'+'\ntext')
    note(v,'articles/a.typ','Article','https://a.test/x','== Summary\nA sufficiently long useful summary sentence.\n')
    note(v,'articles/b.typ','Article','https://b.test/x','== Summary\nShort. And then a longer second sentence here.\n')
    note(v,'articles/c.typ','Same','https://c.test/x','== Same\n')
    note(v,'articles/d.typ','Same','https://d.test/x','== Same\n')
    rows,calls=vat.collect(v,chat=lambda m:('{"title":"Model Discovery"}','m','c'))
    by={Path(x['file']).name:x for x in rows}
    assert by['example.com - Example.com.typ']['method']=='offline-heading'
    assert by['a.typ']['method']=='offline-summary'
    assert by['b.typ']['method']=='model'
    assert by['c.typ']['method']=='kept-shared' or by['d.typ']['method']=='kept-shared'
    assert calls==1


def test_dry_apply_revert_exact_and_refs(tmp_path,monkeypatch):
    monkeypatch.setenv('VAULT_DEDUPE_SKIP_APP_CHECK','1')
    v=tmp_path/'vault'; p=note(v,'articles/example.com - Article.typ','Article','https://example.com/a','== A Much Better Title Here\r\nBody bytes\r\n')
    original=p.read_bytes(); job=v/'_system/jobs/job.json'; job.parent.mkdir(parents=True); job.write_text(json.dumps({'note_path':'articles/example.com - Article.typ'}))
    before={x.relative_to(v).as_posix():x.read_bytes() for x in v.rglob('*') if x.is_file()}
    rows,_=vat.collect(v,no_model=True)
    assert {x.relative_to(v).as_posix():x.read_bytes() for x in v.rglob('*') if x.is_file()}==before
    backup=tmp_path/'backup'; manifest=tmp_path/'manifest.json'
    vat.apply_plan(v,rows,backup,manifest)
    dest=v/'articles/example.com - A Much Better Title Here.typ'
    parsed=vd.parse_note(dest)
    assert parsed['title']=='A Much Better Title Here'
    changed=dest.read_bytes().decode()
    assert changed.count('title: "A Much Better Title Here",')==1 and '= A Much Better Title Here\r\n' in changed
    assert 'Body bytes\r\n' in changed
    expected=original.decode().replace('title: "Article",','title: "A Much Better Title Here",',1).replace('= Article\n','= A Much Better Title Here\n',1)
    assert changed==expected
    assert json.loads(job.read_text())['note_path']=='articles/example.com - A Much Better Title Here.typ'
    vat.vf.revert(manifest,v,apply=True)
    assert {x.relative_to(v).as_posix():x.read_bytes() for x in v.rglob('*') if x.is_file()}==before


def test_model_cap_and_no_model(tmp_path):
    v=tmp_path/'v'
    for i in range(3): note(v,f'articles/{i}.typ','Article',f'https://x.test/{i}','== Summary\nShort. And then a longer second sentence here.\n')
    calls=[]
    chat=lambda m:(calls.append(m) or ('{"title":"Useful Model Title"}','m','c'))
    rows,used=vat.collect(v,chat=chat,max_model_calls=1)
    assert used==1 and len(calls)==1
    rows,used=vat.collect(v,chat=chat,no_model=True)
    assert used==0 and len(calls)==1


def test_real_pipeline_rules_if_installed():
    real=Path(os.environ.get('PIPELINE_SRC','~/Nextcloud/scripts/article-pipeline/src')).expanduser()/'article_pipeline/titles.py'
    if not real.exists(): pytest.skip('article pipeline title rules unavailable')
    assert real.is_file()
