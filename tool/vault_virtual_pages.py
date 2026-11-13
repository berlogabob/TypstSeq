#!/usr/bin/env python3
"""Create missing referenced pages and repoint legacy Typst note links."""
from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
from collections import Counter, defaultdict
from pathlib import Path
import re
import sys
import unicodedata

from vault_dedupe import atomic_write, backup_file, iter_notes, parse_note, require_app_closed
from vault_filenames import clean_stem, _key, revert

REF = re.compile(r'#tylog\.ref-note\("((?:\\.|[^"\\])*)"\)')
DEAD_ID = re.compile(r'^(?:md|obs)-[0-9a-f]{8,}(?:-\d+)?$')
DATE_ISO = re.compile(r'^\d{4}-\d{2}-\d{2}$')
DATE_COMPACT = re.compile(r'^(\d{4})(\d{2})(\d{2})$')
MONTHS = {m.casefold(): i for i, m in enumerate(("January February March April May June July August September October November December").split(), 1)}
MONTHS.update({k[:3]: v for k, v in list(MONTHS.items())})
DATE_WORD = re.compile(r'^([A-Za-z]+)\s+(\d{1,2})(?:st|nd|rd|th),\s*(\d{4})$', re.I)


def unescape(s):
    return re.sub(r'\\(.)', r'\1', s)


def quote(s):
    return '"' + s.replace('\\', '\\\\').replace('"', '\\"') + '"'


def markup(s):
    return ''.join('\\' + c if c in r'\#[]$*_@<>`~/' else c for c in s)


def stamp_now():
    return dt.datetime.now().strftime('%Y%m%d-%H%M%S')


def normalize_date(target):
    if DATE_ISO.fullmatch(target):
        try: return dt.date.fromisoformat(target).isoformat()
        except ValueError: return None
    m = DATE_COMPACT.fullmatch(target)
    if m:
        try: return dt.date(*(int(x) for x in m.groups())).isoformat()
        except ValueError: return None
    m = DATE_WORD.fullmatch(target)
    if m:
        month = MONTHS.get(m.group(1).casefold())
        if month:
            try: return dt.date(int(m.group(3)), month, int(m.group(2))).isoformat()
            except ValueError: return None
    return None


def source(ident, title):
    return ('#import "/_system/tylog.typ" as tylog\n\n#show: tylog.note.with(\n'
            f'  id: {quote(ident)},\n  title: {quote(title)},\n  kind: "note",\n  tags: (),\n)\n\n= {markup(title)}\n\n')


def note_files(vault):
    for p in sorted(Path(vault).rglob('*.typ')):
        rel = p.relative_to(vault)
        if not any(part.startswith(('_', '.')) for part in rel.parts):
            yield p


def plan(vault, min_links=2, stamp=None, singletons_out=None):
    vault = Path(vault); stamp = stamp or stamp_now()
    notes = [n for n in iter_notes(vault) if 'error' not in n]
    ids = {n['id'] for n in notes if n['id']}
    title_exact, title_fold = defaultdict(list), defaultdict(list)
    for n in notes:
        title_exact[n['title']].append(n); title_fold[n['title'].casefold()].append(n); title_fold[clean_stem(n['title']).casefold()].append(n)
    occurrences = defaultdict(list)
    for n in notes:
        for m in REF.finditer(n['text']): occurrences[unescape(m.group(1))].append(n['path'].relative_to(vault).as_posix())
    dead = {t: paths for t, paths in occurrences.items() if t not in ids}
    # Case variants ("AI"/"ai") are one page on a case-insensitive volume: merge
    # them under the most-linked spelling and point every variant at the result.
    groups = defaultdict(list)
    for t in dead: groups[t.strip().casefold()].append(t)
    alias = {}
    for variants in groups.values():
        if len(variants) < 2: continue
        canon = max(sorted(variants), key=lambda t: len(dead[t]))
        dead[canon] = sum((dead[t] for t in variants), [])
        for t in variants:
            if t != canon: alias[t] = canon; del dead[t]
    mapping, skipped, journal, matched, stubs, singletons = {}, defaultdict(list), [], [], [], []
    reserved_ids = set(ids); used_names = {_key(p.name) for p in (vault / 'notes').glob('*.typ')} if (vault / 'notes').exists() else set()
    for target in sorted(dead):
        count = len(dead[target])
        if not target.strip(): skipped['empty'].append(target); continue
        if '/' in target or '\\' in target: skipped['path'].append(target); continue
        if not any(c.isalnum() for c in target): skipped['no-alnum'].append(target); continue
        if DEAD_ID.fullmatch(target): skipped['dead-id'].append(target); continue
        date = normalize_date(target)
        if date:
            if date in ids: mapping[target] = date; journal.append({'target': target, 'id': date, 'count': count, 'status': 'handled'})
            else: journal.append({'target': target, 'id': date, 'count': count, 'status': 'missing'})
            continue
        matches = title_exact.get(target, [])
        if not matches:
            cands = {id(x): x for k in (target.casefold(), clean_stem(target).casefold()) for x in title_fold.get(k, [])}
            if len(cands) == 1: matches = list(cands.values())
        if len(matches) == 1:
            mapping[target] = matches[0]['id']; matched.append({'target': target, 'id': matches[0]['id'], 'count': count})
            continue
        if len(matches) > 1: skipped['ambiguous'].append(target); continue
        if count < min_links:
            singletons.append({'target': target, 'file': sorted(set(dead[target]))[0], 'count': count}); continue
        title = target.strip(); stem = clean_stem(title)
        if stem == 'Untitled' and title != 'Untitled': skipped['bad-name'].append(target); continue
        base = stem; suffix = 2
        while _key(stem + '.typ') in used_names or (vault / 'notes' / (stem + '.typ')).exists():
            stem = f'{base} {suffix}'; suffix += 1
        used_names.add(_key(stem + '.typ'))
        slug = re.sub(r'[^a-z0-9]+', '-', title.lower()).strip('-')
        base_id = stamp + ('-' + slug if slug else '')
        ident = base_id; suffix = 2
        while ident in reserved_ids:
            ident = f'{base_id}-{suffix}'; suffix += 1
        reserved_ids.add(ident)
        rel = f'notes/{stem}.typ'
        mapping[target] = ident
        stubs.append({'target': target, 'path': rel, 'id': ident, 'count': count, 'title': title, 'text': source(ident, title)})
    for variant, canon in alias.items():
        if canon in mapping: mapping[variant] = mapping[canon]
    if singletons_out:
        Path(singletons_out).parent.mkdir(parents=True, exist_ok=True)
        Path(singletons_out).write_text(''.join(f"{x['target']}\t{x['file']}\n" for x in sorted(singletons, key=lambda x:x['target'])), encoding='utf-8')
    edits = {}
    for p in note_files(vault):
        text = p.read_text(encoding='utf-8'); changed = 0
        def replace(m):
            nonlocal changed
            target = unescape(m.group(1))
            if target not in mapping: return m.group(0)
            changed += 1
            encoded = mapping[target].replace('\\', '\\\\').replace('"', '\\"')
            return m.group(0)[:m.start(1)-m.start()] + encoded + m.group(0)[m.end(1)-m.start():]
        updated = REF.sub(replace, text)
        if updated != text: edits[p.relative_to(vault).as_posix()] = {'text': updated, 'count': changed}
    return {'vault': str(vault), 'stamp': stamp, 'note_count': len(notes), 'dead_target_count': len(dead), 'mapping': mapping, 'stubs': stubs, 'edits': edits, 'journal': journal, 'existing_title': matched, 'singletons': singletons, 'skipped': {k: sorted(v) for k,v in skipped.items()}, 'remaining': sum(len(v) for t,v in dead.items() if t not in mapping)}


def apply_plan(result, backup, manifest):
    vault = Path(result['vault']); require_app_closed(); backup = Path(backup)
    doc = {'version': 1, 'renames': [], 'ref_edits': [], 'ref_moves': [], 'creates': [], 'backup': str(backup)}
    for stub in result['stubs']:
        path = vault / stub['path']; path.parent.mkdir(parents=True, exist_ok=True)
        data = stub['text']; path.write_text(data, encoding='utf-8', newline='')
        doc['creates'].append({'path': stub['path'], 'sha256': hashlib.sha256(data.encode()).hexdigest()})
    for rel, edit in sorted(result['edits'].items()):
        path = vault / rel; backup_file(vault, rel, backup); atomic_write(path, edit['text'])
        doc['ref_edits'].append({'file': rel, 'backup': rel})
        if len(doc['ref_edits']) % 200 == 0: write_manifest(manifest, doc)
    write_manifest(manifest, doc)
    return doc


def write_manifest(path, doc):
    p = Path(path); p.parent.mkdir(parents=True, exist_ok=True)
    data = json.dumps(doc, ensure_ascii=False, indent=2) + '\n'
    if p.exists(): atomic_write(p, data)
    else: p.write_text(data, encoding='utf-8')


def report(result):
    categories = {'created_stubs': len(result['stubs']), 'links_to_repoint': sum(x['count'] for x in result['stubs']) + sum(x['count'] for x in result['existing_title']) + sum(x['count'] for x in result['journal'] if x['status']=='handled'), 'journal_handled': sum(x['status']=='handled' for x in result['journal']), 'journal_missing': sum(x['status']=='missing' for x in result['journal']), 'existing_title_repoints': len(result['existing_title']), 'singletons': len(result['singletons']), 'skipped': {k: {'count':len(v), 'top10': sorted(v, key=lambda t: (-sum(1 for x in result['mapping'] if x==t), t))[:10]} for k,v in result['skipped'].items()}}
    return categories


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument('vault', nargs='?'); ap.add_argument('--min-links', type=int, default=2); ap.add_argument('--singletons-out'); ap.add_argument('--report-out'); ap.add_argument('--stamp'); ap.add_argument('--apply', action='store_true'); ap.add_argument('--backup'); ap.add_argument('--manifest'); ap.add_argument('--revert')
    args = ap.parse_args(argv)
    if args.revert:
        if not args.vault: ap.error('VAULT required with --revert')
        print(json.dumps(revert(args.revert, args.vault, args.apply), indent=2)); return 0
    if not args.vault: ap.error('VAULT is required')
    if args.apply and (not args.backup or not args.manifest): ap.error('--apply requires --backup and --manifest')
    result = plan(args.vault, args.min_links, args.stamp, args.singletons_out)
    summary = report(result)
    output = {'summary': summary, 'stubs': [{k:v for k,v in x.items() if k!='text'} for x in result['stubs']], 'repointed': {k:v['count'] for k,v in result['edits'].items()}, 'journal': result['journal'], 'existing_title': result['existing_title'], 'singletons': result['singletons'], 'skipped': result['skipped'], 'remaining_dead_links': result['remaining']}
    print(json.dumps(summary, ensure_ascii=False, indent=2)); print('stubs:')
    for x in result['stubs'][:40]: print(f"{x['target']} -> {x['path']} ({x['id']}, {x['count']} links)")
    print(f"remaining dead links after change: {result['remaining']}")
    if args.report_out: Path(args.report_out).write_text(json.dumps(output, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
    if args.apply: apply_plan(result, args.backup, args.manifest)
    return 0

if __name__ == '__main__': raise SystemExit(main())
