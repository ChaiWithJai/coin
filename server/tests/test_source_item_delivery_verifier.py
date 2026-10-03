import json
import sqlite3
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from batch_jobs import Store
from source_item_delivery_verifier import attempt_event_id, verify_delivery
from telemetry import Outbox


def valid_payload(job, item):
    attempt = {'attempt_kind': 'deterministic_rule', 'inference_performed': False,
               'cache_hit': False, 'usage': {'total_tokens': 0},
               'actual_cost_usd': None, 'estimated_cost_usd': None,
               'cost_status': {'actual': 'unknown', 'estimated': 'unknown'}}
    common = {'job_id': job, 'item_id': item}
    return {'decision': {'telemetry_schema_version': 'source-item-attempt-v1',
                         'runtime_eligible': False, 'runtime_promotion': False},
            'stages': [
                {'name': 'source_item.normalization', 'inputs': common,
                 'outputs': {'source_lineage': {'source_item_id': 'source',
                                                'normalization_version': 'v1'},
                             'attempt': attempt}},
                {'name': 'source_item.gate_decision',
                 'outputs': {'runtime_promotion': False}},
                {'name': 'source_item.human_review',
                 'outputs': {'state': 'not_performed'}},
                {'name': 'source_item.promotion_decision',
                 'outputs': {'decision': 'not_promoted'}},
            ]}


class DeliveryVerifierTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.batch = Path(self.tmp.name) / 'batch.sqlite'
        self.outbox = Path(self.tmp.name) / 'outbox.sqlite'
        store = Store(self.batch)
        with store.db() as db:
            db.execute('INSERT INTO jobs VALUES(?,?,?,?,?)',
                       ('job', '{}', '{}', 'pending', 0))
            for item, state in [('one', 'complete'), ('two', 'failed'),
                                ('later', 'pending')]:
                db.execute('INSERT INTO items(job_id,item_id,kind,input,state,attempts) VALUES(?,?,?,?,?,?)',
                           ('job', item, 'source_item', '{}', state,
                            1 if state != 'pending' else 0))
            db.execute('INSERT INTO attempts VALUES(?,?,?,?,?,?,?)',
                       ('job', 'one', 1, 'complete', '{}', None, '{}'))
            db.execute('INSERT INTO attempts VALUES(?,?,?,?,?,?,?)',
                       ('job', 'two', 1, 'failed', None, '{}', '{}'))
        box = Outbox(self.outbox)
        self.one = attempt_event_id('job', 'one', 1)
        self.two = attempt_event_id('job', 'two', 1)
        box.enqueue(valid_payload('job', 'one'), self.one)
        claimed = box.claim(now=1)
        box.finish(claimed, True, now=1)

    def test_reconciles_pending_missing_duplicate_and_coverage(self):
        payload = valid_payload('job', 'one')
        def reader(experiment, event_ids):
            self.assertEqual(experiment, '40')
            return [
                {'event_id': self.one, 'status': 'FINISHED',
                 'trace_id': 'trace-a', 'payload': payload},
                {'event_id': self.one, 'status': 'FINISHED',
                 'trace_id': 'trace-b', 'payload': payload},
                {'event_id': self.two, 'status': 'RUNNING',
                 'trace_id': 'trace-c', 'payload': {}},
            ]
        report = verify_delivery(self.batch, self.outbox, 'job', reader)
        self.assertEqual(report['expected_attempt_count'], 2)
        self.assertEqual(report['attempt_states'], {'complete': 1, 'failed': 1})
        self.assertEqual(report['pending_job_items'], 1)
        self.assertEqual(report['outbox']['delivered']['event_ids'], [self.one])
        self.assertEqual(report['outbox']['missing']['event_ids'], [self.two])
        self.assertEqual(report['mlflow']['finished']['count'], 1)
        self.assertEqual(report['mlflow']['missing']['event_ids'], [self.two])
        self.assertEqual(report['mlflow']['duplicate_traces']['events'][self.one],
                         ['trace-a', 'trace-b'])
        for name in ('schema', 'lineage', 'runtime_gate', 'usage', 'cost'):
            self.assertEqual(report['outbox_coverage'][name]['covered'], 1)
            self.assertEqual(report['mlflow_coverage'][name]['covered'], 1)

    def test_reports_queued_failed_states_and_malformed_payload(self):
        box = Outbox(self.outbox)
        box.enqueue({}, self.two)
        with sqlite3.connect(self.outbox) as db:
            db.execute("UPDATE events SET state='pending',delivered_at=NULL WHERE id=?",
                       (self.one,))
            db.execute("UPDATE events SET state='failed',last_error='terminal' WHERE id=?",
                       (self.two,))
        report = verify_delivery(self.batch, self.outbox, 'job', lambda *_: [])
        self.assertEqual(report['outbox']['failed']['event_ids'], [self.two])
        self.assertEqual(report['outbox']['queued']['event_ids'], [self.one])
        self.assertEqual(report['outbox_coverage']['schema']['covered'], 1)
        self.assertEqual(report['outbox_coverage']['schema']['missing_event_ids'],
                         [self.two])

    def test_is_read_only(self):
        before_batch = self.batch.read_bytes()
        before_outbox = self.outbox.read_bytes()
        verify_delivery(self.batch, self.outbox, 'job', lambda *_: [])
        self.assertEqual(self.batch.read_bytes(), before_batch)
        self.assertEqual(self.outbox.read_bytes(), before_outbox)


if __name__ == '__main__':
    unittest.main()
