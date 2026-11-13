"""Temporary-vault tests; no real vault is accessed."""
import json, os, sys, types
from pathlib import Path
import pytest
sys.path.insert(0, str(Path(__file__).resolve().parent))
import vault_junk_articles as vj


def note(root, name, title="Article", url="https://example.com/x", status="unread", props="", body="== Summary\nUseful summary\n#line(length: 100%)\n"+"a"*220+"\n"):
    fields=f'  id: "{name}",\n  title: "{title}",\n  kind: "article",\n  properties: ("url": "{url}", "status": "{status}"{props}),\n'
    p=root/"articles"/(name+".typ"); p.parent.mkdir(parents=True,exist_ok=True)
    p.write_text('#show: tylog.note.with(\n'+fields+')\n= '+title+'\n'+body,encoding='utf-8'); return p


def pipeline(monkeypatch, junk=None, generic=None):
    pkg=types.ModuleType('article_pipeline'); pkg.__path__=[]
    proc=types.ModuleType('article_pipeline.processor'); proc.junk_reason=junk or (lambda t,u: None)
    titles=types.ModuleType('article_pipeline.titles'); titles.is_generic_title=generic or (lambda t,h,n=(): t in ('Article','Example'))
    net=types.ModuleType('article_pipeline.net'); net.normalize_url=lambda u:u.lower().rstrip('/')
    monkeypatch.setitem(sys.modules,'article_pipeline',pkg); monkeypatch.setitem(sys.modules,'article_pipeline.processor',proc); monkeypatch.setitem(sys.modules,'article_pipeline.titles',titles); monkeypatch.setitem(sys.modules,'article_pipeline.net',net)


def test_detection_classes_and_lazy_import_failure(tmp_path, monkeypatch):
    pipeline(monkeypatch, junk=lambda t,u:'captcha detected')
    a=note(tmp_path,'a','Prove your humanity',body='Please accept cookie consent\n== Summary\n#line(length: 100%)\n')
    n=vj.vd.parse_note(a)
    assert any('pipeline' in x for x in vj.detect(n,vj._pipeline()))
    assert any('shell/error' in x for x in vj.detect(n,vj._pipeline()))
    assert any('cookie/consent' in x for x in vj.detect(n,vj._pipeline()))
    h=note(tmp_path,'h','Хабр','https://habr.com/post',body='== Summary\nError 403\n#line(length: 100%)\n')
    assert any('Habr' in x for x in vj.detect(vj.vd.parse_note(h),vj._pipeline()))
    monkeypatch.setattr(vj,'PIPELINE_SRC',tmp_path/'missing')
    for mod in ('article_pipeline.processor','article_pipeline.titles','article_pipeline.net'): monkeypatch.delitem(sys.modules,mod,raising=False)
    assert 'junk_reason skipped' in vj._pipeline()[3]


def test_generic_and_empty_detection(tmp_path, monkeypatch):
    pipeline(monkeypatch)
    p=note(tmp_path,'g','Article',body='== Summary\nCaptcha required\n#line(length: 100%)\nshort\n')
    reasons=vj.detect(vj.vd.parse_note(p),vj._pipeline())
    assert any('generic title' in r for r in reasons)

    short=note(tmp_path,'short','Article',body='== Summary\nA useful short summary.\n#line(length: 100%)\nshort tweet\n')
    assert not vj.detect(vj.vd.parse_note(short),vj._pipeline())
    empty=note(tmp_path,'empty','A specific title',body='== Summary\n\n== Extracted\n#line(length: 100%)\nshort\n')
    assert 'empty extracted body' in vj.detect(vj.vd.parse_note(empty),vj._pipeline())
    longer=note(tmp_path,'long','A specific title',body='== Summary\nUseful\n#line(length: 100%)\n'+'x'*200+'\n')
    assert 'empty extracted body' not in vj.detect(vj.vd.parse_note(longer),vj._pipeline())


def test_eligibility_delete_ledger_related_assets_and_revert(tmp_path, monkeypatch):
    pipeline(monkeypatch, junk=lambda t,u:'login wall' if t=='Sign in to your account' else None)
    monkeypatch.setenv('VAULT_DEDUPE_SKIP_APP_CHECK','1')
    vault=tmp_path/'vault'; target=note(vault,'junk','Sign in to your account')
    other=note(vault,'other','A real article',url='https://example.com/other')
    with other.open('a') as f: f.write('// tylog:auto-related\n== Related\n- #tylog.ref-note("junk")[junk]\n')
    asset=vault/'assets/articles/junk/image.png'; asset.parent.mkdir(parents=True); asset.write_bytes(b'asset')
    original={p.relative_to(vault).as_posix():p.read_bytes() for p in vault.rglob('*') if p.is_file()}
    rows,_=vj.collect(vault); assert rows[0]['eligible']
    ledger=tmp_path/'ledger.jsonl'; ledger.write_text('{"normalized":"https://different.test/"}\n')
    # distinct normalized URL is appended
    backup=tmp_path/'backup'; manifest=tmp_path/'manifest.json'
    doc=vj.apply(vault,rows,backup,manifest,ledger)
    assert not target.exists() and not asset.exists()
    assert b'ref-note("junk")' not in other.read_bytes()
    assert len(doc['ledger_lines'])==1
    assert (backup/'assets/articles/junk/image.png').read_bytes()==b'asset'
    vj.vf.revert(manifest,vault,apply=True)
    after={p.relative_to(vault).as_posix():p.read_bytes() for p in vault.rglob('*') if p.is_file()}
    assert after==original
    assert ledger.read_text()=='{"normalized":"https://different.test/"}\n'


def test_ineligible_reasons(tmp_path, monkeypatch):
    pipeline(monkeypatch, junk=lambda t,u:'junk')
    v=tmp_path/'v'
    note(v,'status',status='read'); note(v,'rating',props=', "rating": "5"'); note(v,'edited',props=', \"custom\": \"edited\"')
    n=note(v,'linked'); note(v,'inc')
    (v/'articles/bodylink.typ').write_text('#show: something\n#tylog.ref-note("linked")[linked]\n')
    (v/'articles/include.typ').write_text('#include "/articles/inc.typ"\n')
    rows,_=vj.collect(v); by={r['id']:r for r in rows}
    assert not by['status']['eligible'] and 'status=read' in by['status']['ineligible_reasons']
    assert not by['rating']['eligible']
    assert not by['edited']['eligible']
    assert not by['linked']['eligible']
    assert not by['inc']['eligible']


def test_digest_links_do_not_block_and_are_removed_with_backup_revert(tmp_path, monkeypatch):
    pipeline(monkeypatch, junk=lambda t,u:'junk')
    monkeypatch.setenv('VAULT_DEDUPE_SKIP_APP_CHECK','1')
    vault=tmp_path/'vault'; target=note(vault,'target')
    digest=note(vault,'digest-week-1','Weekly digest',url='https://example.com/digest')
    line='- #tylog.ref-note("target")[Target] — example.com\n'
    digest.write_text(digest.read_text()+line,encoding='utf-8')
    original=digest.read_bytes()
    rows,_=vj.collect(vault); row=next(r for r in rows if r['id']=='target')
    assert row['eligible'] and row['inbound_link_count']==0
    manifest=tmp_path/'manifest.json'; backup=tmp_path/'backup'
    vj.apply(vault,[row],backup,manifest,tmp_path/'ledger')
    assert not target.exists() and line.encode() not in digest.read_bytes()
    assert (backup/'articles/digest-week-1.typ').read_bytes()==original
    vj.vf.revert(manifest,vault,apply=True)
    assert target.exists() and digest.read_bytes()==original


def test_ledger_dedupe(tmp_path, monkeypatch):
    pipeline(monkeypatch, junk=lambda t,u:'bad')
    v=tmp_path/'v'; note(v,'x')
    ledger=tmp_path/'ledger'; ledger.write_text('{"normalized":"https://example.com/x"}\n')
    rows,_=vj.collect(v); doc=vj.apply(v,rows,tmp_path/'b',tmp_path/'m',ledger)
    assert doc['ledger_lines']==[]
