import io
import json
from urllib.error import HTTPError

import lab_bridge


class FakeDB:
    def __init__(self):
        self.tables = {'assets': [{'id': 2, 'item_id': 3, 'tag': 'TL-1'},
                                  {'id': 4, 'item_id': 5, 'tag': 'TL-2'}],
                       'asset_place': [{'asset_id': 2, 'place_id': 6}, {'asset_id': 4, 'place_id': 7}],
                       'people': [{'id': 8, 'name': 'José Silva'}], 'movements': []}
        self.refusal = None

    def select(self, table, **params):
        return [row.copy() for row in self.tables[table]
                if all(str(row.get(key)) == value[3:] for key, value in params.items()
                       if value.startswith('eq.'))]

    def insert(self, movement):
        if self.refusal:
            raise HTTPError('url', 400, 'Bad Request', {},
                            io.BytesIO(json.dumps({'message': self.refusal}).encode()))
        row = {'id': len(self.tables['movements']) + 1, **movement}
        self.tables['movements'].append(row)
        return row


def loan(**changes):
    return {'id': 'task-1', 'equipment': ['TL-1'], 'borrower': 'JOSE SILVA',
            'assignees': [], 'start': '2026-11-01T10:00:00Z', 'end': None,
            'open': True, **changes}


def test_issue_exact_movement():
    results = list(lab_bridge.bridge([loan()], FakeDB(), 9))
    assert results == [{'task': 'task-1', 'tag': 'TL-1', 'step': 'out', 'action': 'would record',
                        'movement': {'item_id': 3, 'asset_id': 2, 'qty': 1, 'from_place': 6,
                                     'person_id': 8, 'kind': 'issue', 'at': '2026-11-01T10:00:00Z',
                                     'note': 'tylog:task-1:TL-1:out', 'by_staff': 9}}]


def test_return_and_idempotency():
    db = FakeDB()
    row = loan(open=False, end='2026-11-02T10:00:00Z')
    dry = list(lab_bridge.bridge([row], db, 9))
    assert dry[1]['reason'] == 'out not recorded yet'
    results = list(lab_bridge.bridge([row], db, 9, apply=True))
    assert [r['status'] for r in results] == ['recorded', 'recorded']
    assert db.tables['movements'][1]['to_place'] == db.tables['movements'][0]['from_place']
    assert db.tables['movements'][1]['person_id'] == 8
    assert all(r['action'] == 'skip' for r in lab_bridge.bridge([row], db, 9))


def test_unknown_and_fallback_person():
    db = FakeDB()
    result = list(lab_bridge.bridge([loan(borrower='Nobody')], db))[0]
    assert result['reason'] == 'no such person: Nobody'
    result = list(lab_bridge.bridge([loan(borrower='Nobody', assignees=['Jose Silva'])], db))[0]
    assert result['movement']['person_id'] == 8
    db.tables['people'].append({'id': 10, 'name': 'Jose Silva'})
    assert list(lab_bridge.bridge([loan()], db))[0]['reason'] == 'ambiguous person: JOSE SILVA'


def test_two_tags_and_refusal():
    db = FakeDB()
    results = list(lab_bridge.bridge([loan(equipment=['TL-1', 'TL-2'])], db, 9))
    assert [r['movement']['note'] for r in results] == ['tylog:task-1:TL-1:out', 'tylog:task-1:TL-2:out']
    db.refusal = 'TL-1 is already out with José'
    result = list(lab_bridge.bridge([loan()], db, 9, apply=True))[0]
    assert result['status'] == 'refused'
    assert result['reason'] == db.refusal


def test_cli_dry_run_and_apply_log(tmp_path, monkeypatch, capsys):
    db = FakeDB()
    monkeypatch.setattr(lab_bridge, 'Database', lambda url, key: db)
    source, env, vault = tmp_path / 'loans.jsonl', tmp_path / 'env', tmp_path / 'vault'
    source.write_text(json.dumps(loan()) + '\n', encoding='utf-8')
    env.write_text('SUPABASE_URL=https://example.com\nSUPABASE_SERVICE_KEY=secret\n', encoding='utf-8')
    args = ['--jsonl', str(source), '--vault', str(vault), '--env-file', str(env), '--device', 'test']
    lab_bridge.main(args)
    assert json.loads(capsys.readouterr().out)['action'] == 'would record'
    assert not vault.exists()
    db.refusal = 'already out'
    lab_bridge.main(args + ['--apply', '--staff-id', '9'])
    log = vault / '_system/lab/results/test.jsonl'
    result = json.loads(log.read_text(encoding='utf-8'))
    assert result['status'] == 'refused' and result['reason'] == 'already out'
    assert result['at']


def test_apply_log_records_only_changes(tmp_path, monkeypatch):
    db = FakeDB()
    monkeypatch.setattr(lab_bridge, 'Database', lambda url, key: db)
    source, env, vault = tmp_path / 'loans.jsonl', tmp_path / 'env', tmp_path / 'vault'
    source.write_text(json.dumps(loan(borrower='Nobody')) + '\n' + json.dumps(loan(id='task-2')) + '\n', encoding='utf-8')
    env.write_text('SUPABASE_URL=https://example.com\nSUPABASE_SERVICE_KEY=secret\n', encoding='utf-8')
    args = ['--jsonl', str(source), '--vault', str(vault), '--env-file', str(env), '--device', 'test', '--apply', '--staff-id', '9']
    lab_bridge.main(args)
    lab_bridge.main(args)
    log = [json.loads(line) for line in (vault / '_system/lab/results/test.jsonl').read_text(encoding='utf-8').splitlines()]
    assert [(r['task'], r['status']) for r in log] == [('task-1', 'skipped'), ('task-2', 'recorded')]
