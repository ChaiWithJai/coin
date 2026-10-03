import json
import sqlite3
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from batch_jobs import Store
from source_item_audit import audit_source_item_job, semantic_review_queue


def catalog():
    return {'catalogVersion': 'fixture-v1', 'sourceURL': 'https://example.test',
            'workouts': [{'id': 'day', 'sourceSHA256': 'a' * 64, 'blocks': [
                {'id': 'block', 'kind': 'exercise', 'sourceText': 'JUMP SQUATS',
                 'sourceItems': [{'id': 'item', 'text': 'JUMP SQUATS'}]},
            ]}]}


class SourceItemAuditTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.path = Path(self.temp.name) / 'batch.sqlite'
        self.store = Store(self.path)
        self.job = self.store.submit_source_items(catalog())

    def test_complete_deterministic_job_passes_and_sample_is_stable(self):
        first = audit_source_item_job(self.path, self.job, 1)
        second = audit_source_item_job(self.path, self.job, 1)
        self.assertTrue(first['passed'])
        self.assertEqual(first, second)
        self.assertEqual(first['counts']['complete'], 1)
        self.assertEqual(first['usage']['total_tokens'], 0)
        self.assertEqual(first['runtime_eligibility']['eligible_items'], 0)
        sample = first['semantic_high_confidence_sample']
        self.assertEqual(sample['sample_size'], 1)
        self.assertEqual(sample['items'][0]['semantic_review_state'], 'not_reviewed')
        queue = semantic_review_queue(first)
        self.assertEqual(queue['count'], 1)
        self.assertFalse(queue['runtime_eligible'])
        self.assertEqual(queue['items'][0]['proposal_activity'], 'strength')
        self.assertEqual(queue['items'][0]['source_item_id'], 'item')

    def test_identity_usage_and_runtime_tampering_fail(self):
        with sqlite3.connect(self.path) as db:
            raw = db.execute('SELECT output FROM items WHERE job_id=?', (self.job,)).fetchone()[0]
            output = json.loads(raw)
            output['result']['source_item_id'] = 'other'
            output['result']['runtime_eligible'] = True
            output['usage']['total_tokens'] = 2
            db.execute('UPDATE items SET output=? WHERE job_id=?',
                       (json.dumps(output), self.job))
        report = audit_source_item_job(self.path, self.job)
        self.assertFalse(report['passed'])
        codes = [issue['code'] for issue in report['issues']]
        self.assertIn('result_source_identity_mismatch', codes)
        self.assertIn('runtime_eligible_not_false', codes)
        self.assertIn('usage_total_mismatch', codes)
        self.assertIn('non_inference_usage_not_zero', codes)

    def test_incomplete_job_fails_closed(self):
        with sqlite3.connect(self.path) as db:
            db.execute("UPDATE jobs SET state='paused' WHERE id=?", (self.job,))
            db.execute("UPDATE items SET state='pending',output=NULL WHERE job_id=?", (self.job,))
        report = audit_source_item_job(self.path, self.job)
        self.assertFalse(report['passed'])
        self.assertEqual(report['counts']['pending'], 1)
        self.assertEqual({i['code'] for i in report['issues']},
                         {'job_not_complete', 'item_not_complete'})


if __name__ == '__main__':
    unittest.main()
