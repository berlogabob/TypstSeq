import hashlib
import json
import shutil
import subprocess
from pathlib import Path

import pytest

import vault_virtual_pages as vp
from vault_dedupe import parse_note
import vault_filenames as vf


def note(path, ident, title, body=''):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(f'#import "/_system/tylog.typ" as tylog\n\n#show: tylog.note.with(\n  id: "{ident}",\n  title: "{title}",\n  kind: "note",\n  tags: (),\n)\n\n= {title}\n\n{body}', encoding='utf-8')


def test_template_escaping_ids_and_parsing(tmp_path):
    v=tmp_path/'vault'
    ref = r'#tylog.ref-note("A \"q\" # title")[label]'
    note(v/'notes'/'source.typ','source','Source', ref+'\n'+ref+'\n#tylog.ref-note("Кириллица")[x]\n#tylog.ref-note("Кириллица")[y]\n#tylog.ref-note("Бета")[x]\n#tylog.ref-note("Бета")[y]\n')
    r=vp.plan(v, stamp='20261113-123456')
    by={x['target']:x for x in r['stubs']}
    title='A "q" # title'
    assert by[title]['text']==('#import "/_system/tylog.typ" as tylog\n\n#show: tylog.note.with(\n  id: "20261113-123456-a-q-title",\n  title: "A \\\"q\\\" # title",\n  kind: "note",\n  tags: (),\n)\n\n= A "q" \\# title\n\n')
    assert by['Бета']['id']=='20261113-123456'
    assert by['Кириллица']['id']=='20261113-123456-2'
    assert parse_note(Path('/tmp/stub.typ'), by[title]['text'])['id']==by[title]['id']


def test_collision_singletons_dates_titles_and_skips(tmp_path):
    v=tmp_path/'vault'; note(v/'notes'/'src.typ','src','Source','\n'.join(f'#tylog.ref-note("{x}")[L]' for x in ['Blender','Blender','One','20261112','20261112','Nov 12th, 2026','Nov 12th, 2026','Oct 13th, 2022','Oct 13th, 2022','md-12345678','a/b','','!!!','blender']))
    note(v/'notes'/'daily.typ','2026-11-12','day')
    note(v/'notes'/'title.typ','title-id','Blender')
    note(v/'notes'/'Blender.typ','other-id','Occupied')
    r=vp.plan(v, stamp='20261113-123456', singletons_out=tmp_path/'singles.tsv')
    assert r['mapping']['Blender']=='title-id'
    assert r['journal']==[{'target':'20261112','id':'2026-11-12','count':2,'status':'handled'}, {'target':'Nov 12th, 2026','id':'2026-11-12','count':2,'status':'handled'}, {'target':'Oct 13th, 2022','id':'2022-10-13','count':2,'status':'missing'}]
    assert set(r['skipped']) >= {'dead-id','path','empty','no-alnum'}
    assert 'One\tnotes/src.typ\n' in (tmp_path/'singles.tsv').read_text()


def test_repoint_changes_only_target_and_apply_revert(tmp_path, monkeypatch):
    v=tmp_path/'vault'; original='#import "/_system/tylog.typ" as tylog\n\n#show: tylog.note.with(\n  id: "src",\n  title: "Source",\n  kind: "note",\n  tags: (),\n)\n\n= Source\n\n#tylog.ref-note("Blender")[label] tail\n#tylog.ref-note("Blender")[again]\n'
    p=v/'notes'/'source.typ'; p.parent.mkdir(parents=True); p.write_text(original)
    r=vp.plan(v, stamp='20261113-123456')
    assert r['edits']['notes/source.typ']['text']==original.replace('ref-note("Blender")','ref-note("20261113-123456-blender")')
    assert p.read_text()==original
    monkeypatch.setenv('VAULT_DEDUPE_SKIP_APP_CHECK','1')
    backup=tmp_path/'backup'; manifest=tmp_path/'manifest.json'
    doc=vp.apply_plan(r,backup,manifest)
    assert parse_note(p)['id']=='src'
    stub=v/'notes'/'Blender.typ'; assert parse_note(stub)['title']=='Blender'
    assert vf.revert(manifest,v,apply=True)['completed']==2
    assert p.read_bytes()==original.encode() and not stub.exists()


def test_collision_safe_filenames_and_id_collisions(tmp_path):
    v=tmp_path/'v'; note(v/'notes'/'source.typ','source','Source','\n'.join(f'#tylog.ref-note("{x}")[x]' for x in ['Я','Я','Ж','Ж']))
    (v/'notes').mkdir(exist_ok=True); (v/'notes'/'Я.typ').write_text('occupied')
    r=vp.plan(v,stamp='20261113-123456')
    assert [x['id'] for x in r['stubs']]==['20261113-123456','20261113-123456-2']
    assert [x['path'] for x in r['stubs']]==['notes/Ж.typ','notes/Я 2.typ']


def test_revert_deletes_only_unchanged_creates(tmp_path):
    p=tmp_path/'made'; p.write_text('x'); m=tmp_path/'m.json'
    m.write_text(json.dumps({'version':1,'renames':[],'ref_edits':[],'ref_moves':[],'creates':[{'path':'made','sha256':hashlib.sha256(b'x').hexdigest()}]}))
    assert vf.revert(m,tmp_path,apply=True)['completed']==1 and not p.exists()


def test_drop_anchor_stubs_roundtrips_and_preserves_normal_stub(tmp_path, monkeypatch):
    v=tmp_path/'vault'
    originals={}
    body='\n'.join([
        '#tylog.ref-note("#Page 3")[a]', '#tylog.ref-note("#Page 3")[b]',
        '#tylog.ref-note("#Page 4")[c]', '#tylog.ref-note("#Page 4")[d]',
        '#tylog.ref-note("Ordinary topic")[e]', '#tylog.ref-note("Ordinary topic")[f]',
    ])+'\n'
    note(v/'notes'/'source.typ','source','Source',body)
    originals['notes/source.typ']=(v/'notes'/'source.typ').read_bytes()
    # A second source exercises byte-preserving positional restoration across files.
    note(v/'articles'/'other.typ','other','Other',
        '#tylog.ref-note("#Page 3")[x]\n#tylog.ref-note("#Page 4")[y]\n')
    originals['articles/other.typ']=(v/'articles'/'other.typ').read_bytes()
    plan=vp.plan(v, stamp='20261113-123456')
    monkeypatch.setenv('VAULT_DEDUPE_SKIP_APP_CHECK','1')
    job3=tmp_path/'job3.json'; vp.apply_plan(plan,tmp_path/'job3-backup',job3)
    # A changed stub must be skipped and left intact.
    changed=next(x for x in plan['stubs'] if x['target']=='#Page 4')
    changed_path=v/changed['path']; changed_path.write_bytes(changed_path.read_bytes()+b' user edit')
    after_job3={p.relative_to(v).as_posix():p.read_bytes() for p in v.rglob('*.typ') if p.is_file()}
    # Recompute the comparison state with the deliberate user modification.
    anchor3=next(x for x in plan['stubs'] if x['target']=='#Page 3')
    normal=next(x for x in plan['stubs'] if x['target']=='Ordinary topic')
    drop_manifest=tmp_path/'drop.json'
    vp.drop_stubs(v,job3,apply=True,backup=tmp_path/'drop-backup',manifest=drop_manifest)
    assert not (v/anchor3['path']).exists()
    assert changed_path.read_bytes().endswith(b' user edit')
    assert (v/normal['path']).exists()
    assert b'ref-note("#Page 3")' in (v/'notes/source.typ').read_bytes()
    assert b'ref-note("#Page 4")' not in (v/'notes/source.typ').read_bytes()
    assert b'ref-note("#Page 3")' in (v/'articles/other.typ').read_bytes()
    assert vf.revert(drop_manifest,v,apply=True)['completed']==3
    assert {p.relative_to(v).as_posix():p.read_bytes() for p in v.rglob('*.typ') if p.is_file()}==after_job3


def test_typst_compile_when_available(tmp_path):
    typst=shutil.which('typst')
    if not typst: pytest.skip('typst is not installed')
    v=tmp_path/'vault'; note(v/'notes'/'src.typ','src','Source','#tylog.ref-note("Blender")[label]\n#tylog.ref-note("Blender")[label]\n')
    (v/'_system').mkdir(); (v/'_system'/'tylog.typ').write_text('''#let note = (id: "", title: "", kind: "note", tags: (), body) => body\n#let ref-note = (target, label) => label\n''')
    r=vp.plan(v,stamp='20261113-123456')
    stub=v/r['stubs'][0]['path']; stub.parent.mkdir(exist_ok=True); stub.write_text(r['stubs'][0]['text'])
    source=v/'notes'/'src.typ'; source.write_text(r['edits']['notes/src.typ']['text'])
    for path in [stub,source]:
        result=subprocess.run([typst,'compile','--root',str(v),str(path),str(tmp_path/(path.stem+'.pdf'))],capture_output=True,text=True)
        assert result.returncode == 0, result.stderr
