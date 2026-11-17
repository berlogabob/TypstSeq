"""Bridge TyLog loans to OLT: python tool/lab_bridge.py --jsonl FILE --vault DIR --env-file FILE [--apply --staff-id N]."""

import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
import socket
import sys
import unicodedata
from urllib.error import HTTPError
from urllib.parse import urlencode, urlparse
from urllib.request import Request, urlopen


class Database:
    def __init__(self, url, key):
        self.base, self.key = url.rstrip('/') + '/rest/v1', key

    def request(self, method, table, params=None, body=None, headers=None):
        query = '?' + urlencode(params) if params else ''
        req = Request(self.base + '/' + table + query, method=method,
                      data=json.dumps(body).encode() if body is not None else None,
                      headers={'apikey': self.key, 'Authorization': 'Bearer ' + self.key,
                               'Content-Type': 'application/json', **(headers or {})})
        with urlopen(req, timeout=60) as response:
            return json.load(response)

    def select(self, table, **params):
        rows = []
        while True:
            page = self.request('GET', table, params, headers={'Range': f'{len(rows)}-{len(rows) + 999}'})
            rows.extend(page)
            if len(page) < 1000:
                return rows

    def insert(self, movement):
        return self.request('POST', 'movements', body=movement,
                            headers={'Prefer': 'return=representation'})[0]


def fold(name):
    return ''.join(c for c in unicodedata.normalize('NFD', name.casefold())
                   if not unicodedata.combining(c))


def resolve_person(people, names):
    """First name with exactly one OLT person wins; an ambiguous name stops the search (never guess)."""
    reason = 'no such person: '
    for name in filter(None, names):
        matches = [p for p in people if fold(p['name']) == fold(name)]
        if len(matches) == 1:
            return matches[0], None
        reason = ('ambiguous person: ' if matches else 'no such person: ') + name
        if matches:
            break
    return None, reason


def bridge(rows, db, staff_id=None, apply=False):
    people = None
    for row in rows:
        if not row.get('start'):
            continue
        for tag in row['equipment']:
            task = row['id']
            out_note = f'tylog:{task}:{tag}:out'
            out = db.select('movements', select='id,item_id,asset_id,from_place,person_id', note='eq.' + out_note)
            movement, reason, refused = None, None, False
            if out:
                reason = 'already recorded'
            else:
                assets = db.select('assets', select='id,item_id', tag='eq.' + tag)
                if not assets:
                    reason = 'no such asset: ' + tag
                else:
                    asset = assets[0]
                    places = db.select('asset_place', select='place_id', asset_id='eq.' + str(asset['id']))
                    if not places or places[0]['place_id'] is None:
                        reason, refused = 'not on a shelf', True
                    else:
                        if people is None:
                            people = db.select('people', select='id,name', order='id')
                        person, reason = resolve_person(people, [row.get('borrower'), *row.get('assignees', [])])
                        if person:
                            movement = {'item_id': asset['item_id'], 'asset_id': asset['id'], 'qty': 1,
                                        'from_place': places[0]['place_id'], 'person_id': person['id'],
                                        'kind': 'issue', 'at': row['start'], 'note': out_note, 'by_staff': staff_id}
            result = finish(db, task, tag, 'out', movement, reason, refused, apply)
            yield result
            if apply and result['status'] == 'recorded':
                out = [movement]
            if not row.get('open') and row.get('end'):
                note = f'tylog:{task}:{tag}:return'
                existing = db.select('movements', select='id', note='eq.' + note)
                movement, reason = None, None
                if existing:
                    reason = 'already recorded'
                elif not out:
                    reason = 'out not recorded yet'
                else:
                    issue = out[0]
                    movement = {'item_id': issue['item_id'], 'asset_id': issue['asset_id'], 'qty': 1,
                                'to_place': issue['from_place'], 'person_id': issue['person_id'],
                                'kind': 'return', 'at': row['end'], 'note': note, 'by_staff': staff_id}
                yield finish(db, task, tag, 'return', movement, reason, False, apply)


def finish(db, task, tag, step, movement, reason, refused, apply):
    result = {'task': task, 'tag': tag, 'step': step}
    if not apply:
        result['action'] = 'would record' if movement else 'skip'
        if movement:
            result['movement'] = movement
    elif movement:
        try:
            result['status'] = 'recorded'
            result['movement_id'] = db.insert(movement)['id']
        except HTTPError as error:
            if not 400 <= error.code < 500:
                raise
            try:
                reason = json.loads(error.read()).get('message', str(error))
            except (ValueError, UnicodeDecodeError):
                reason = str(error)
            result['status'] = 'refused'
    else:
        result['status'] = 'refused' if refused else 'skipped'
    if reason:
        result['reason'] = reason
    return result


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--jsonl', required=True, type=Path)
    parser.add_argument('--vault', required=True, type=Path)
    parser.add_argument('--env-file', required=True, type=Path)
    parser.add_argument('--staff-id', type=int)
    parser.add_argument('--device', default=socket.gethostname().split('.')[0])
    parser.add_argument('--apply', action='store_true')
    args = parser.parse_args(argv)
    if args.apply and args.staff_id is None:
        parser.error('--staff-id is required with --apply')
    if not args.device or args.device in ('.', '..') or '/' in args.device or '\\' in args.device:
        parser.error('invalid device name')
    try:
        env = {}
        for line in args.env_file.read_text(encoding='utf-8').splitlines():
            line = line.strip()
            if line and not line.startswith('#'):
                key, value = line.split('=', 1)
                env[key.strip()] = value.strip().strip('\"\'')
        url, key = env['SUPABASE_URL'], env['SUPABASE_SERVICE_KEY']
        if not key or urlparse(url).scheme not in ('http', 'https') or not urlparse(url).netloc:
            raise ValueError('invalid Supabase URL or service key')
        rows = [json.loads(line) for line in args.jsonl.read_text(encoding='utf-8').splitlines() if line.strip()]
        for row in rows:
            if not isinstance(row, dict) or not isinstance(row.get('id'), str) or not isinstance(row.get('equipment'), list) or not all(isinstance(t, str) for t in row['equipment']) or not isinstance(row.get('assignees', []), list) or not all(isinstance(n, str) for n in row.get('assignees', [])) or (row.get('borrower') is not None and not isinstance(row['borrower'], str)):
                raise ValueError('invalid loan row')
    except (OSError, ValueError, KeyError) as error:
        parser.exit(2, f'input or environment error: {error}\n')
    db = Database(url, key)
    path = args.vault / '_system/lab/results' / (args.device + '.jsonl')
    # The bridge runs every 30 min: log a step only when its outcome changes, so the synced log stays small.
    last = {}
    if args.apply and path.exists():
        for line in path.read_text(encoding='utf-8').splitlines():
            if line.strip():
                old = json.loads(line)
                last[(old['task'], old['tag'], old['step'])] = (old.get('status'), old.get('reason'))
    for result in bridge(rows, db, args.staff_id, args.apply):
        if not args.apply:
            print(json.dumps(result, ensure_ascii=False))
            continue
        key = (result['task'], result['tag'], result['step'])
        if result.get('reason') == 'already recorded' or last.get(key) == (result['status'], result.get('reason')):
            continue
        last[key] = (result['status'], result.get('reason'))
        path.parent.mkdir(parents=True, exist_ok=True)
        with path.open('a', encoding='utf-8') as stream:
            stream.write(json.dumps({'at': datetime.now(timezone.utc).isoformat(), **result}, ensure_ascii=False) + '\n')


if __name__ == '__main__':
    main()
