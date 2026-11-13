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


def test_model_retitle_language_validation_json_and_changed_since(tmp_path):
    v=tmp_path/'v'; p=note(v,'articles/example.com - Article.typ','Article','https://example.com/story',
        '== Summary\nЭто подробное русское резюме, которое описывает содержание публикации достаточно длинно.\n'+
        ('A long English source paragraph with enough words to establish the original article language and provide useful evidence for the title model. ' * 4)+'\n')
    p2=note(v,'articles/ru.test - Article.typ','Article','https://ru.test/story',
        '== Summary\nРусское подробное резюме о статье и ее содержании для обработки конвейером.\n'+
        'Это оригинальный русский текст статьи, содержащий достаточно букв и слов для определения русского языка и темы публикации.\n')
    plan={'articles':[{'file':'articles/example.com - Article.typ','title':'Article','new_title':'derived one','method':'offline-summary'},
                      {'file':'articles/ru.test - Article.typ','title':'Article','new_title':'derived two','method':'offline-summary'}]}
    (tmp_path/'plan.json').write_text(json.dumps(plan))
    manifest={'renames':[]}; (tmp_path/'manifest.json').write_text(json.dumps(manifest))
    # Align current headings with plan targets.
    for path,title in [(p,'derived one'),(p2,'derived two')]:
        raw=path.read_text().replace('title: "Article"','title: "'+title+'"').replace('= Article','= '+title)
        path.write_text(raw)
    def chat(messages):
        prompt=messages[1]['content']
        return ('Here is my result: {"title":"A Clear English Research Story"}' if 'example.com' in prompt else '{"title":"Новая история исследований"}',None,None)
    rows,kept,calls=vat.retitle_from_manifest(v,tmp_path/'manifest.json',tmp_path/'plan.json',chat)
    assert calls==2 and [r['new_title'] for r in rows]==['A Clear English Research Story','Новая история исследований']
    assert not kept
    # Wrong-language answers remain visible as kept rows.
    rows,kept,calls=vat.retitle_from_manifest(v,tmp_path/'manifest.json',tmp_path/'plan.json',lambda m:('{"title":"Русский заголовок статьи"}',None,None),max_model_calls=1)
    assert calls==1 and kept[0]['reason']=='wrong-language'


@pytest.mark.parametrize('answer,reason', [('Cat','too-short'),('Article','generic'),('A'*81,'too-long')])
def test_model_retitle_rejects_invalid_answers(tmp_path,answer,reason):
    v=tmp_path/'v'; p=note(v,'articles/a.test - Article.typ','Article','https://a.test/x','== Summary\nThis is a sufficiently long English summary used to establish the original source language for the generated title.\nOriginal English article text with enough words to establish a Latin language source and context for the generated title.\n')
    p.write_text(p.read_text().replace('title: "Article"','title: "Derived Title"').replace('= Article','= Derived Title'))
    (tmp_path/'plan.json').write_text(json.dumps({'articles':[{'file':'articles/a.test - Article.typ','title':'Article','new_title':'Derived Title','method':'offline-summary'}]}))
    (tmp_path/'manifest.json').write_text('{"renames":[]}')
    rows,kept,_=vat.retitle_from_manifest(v,tmp_path/'manifest.json',tmp_path/'plan.json',lambda m:(json.dumps({'title':answer}),None,None))
    assert not rows and kept[0]['reason']==reason


def test_model_retitle_changed_since_and_call_cap(tmp_path):
    v=tmp_path/'v';
    for i in range(2):
        p=note(v,f'articles/{i}.typ','Article',f'https://x{i}.test/a','== Summary\nSome sufficiently long summary text that generated a title here.\nSource text is long enough to be evidence for the model and title generation.\n')
        p.write_text(p.read_text().replace('title: "Article"','title: "Edited"').replace('= Article','= Edited'))
    rows=[{'file':f'articles/{i}.typ','title':'Article','new_title':'Expected','method':'offline-summary'} for i in range(2)]
    (tmp_path/'plan.json').write_text(json.dumps({'articles':rows})); (tmp_path/'manifest.json').write_text('{"renames":[]}')
    calls=[]
    out,kept,used=vat.retitle_from_manifest(v,tmp_path/'manifest.json',tmp_path/'plan.json',lambda m:(calls.append(m) or ('{}',None,None)),1)
    assert not calls and used==0 and all(x['reason']=='changed-since' for x in kept)


def test_real_pipeline_rules_if_installed():
    real=Path(os.environ.get('PIPELINE_SRC','~/Nextcloud/scripts/article-pipeline/src')).expanduser()/'article_pipeline/titles.py'
    if not real.exists(): pytest.skip('article pipeline title rules unavailable')
    assert real.is_file()
