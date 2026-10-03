import copy
import json
import sqlite3
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from batch_jobs import Store, digest, normalize_day_six_items


class SourceItemBatchTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.catalog = json.loads((Path(__file__).resolve().parents[2] / 'ios' / 'WorkoutCatalog.json').read_text())

    def source_items(self, catalog):
        workout = next(w for w in catalog['workouts'] if w['id'] == 'basic-w1-d6')
        return next(b for b in workout['blocks'] if b['id'] == 'basic-w1-d6-p8-s1-1')['sourceItems']

    def test_all_ten_source_items_preserve_text_prescription_and_demo_lineage(self):
        before = copy.deepcopy(self.catalog)
        proposals = normalize_day_six_items(self.catalog)
        self.assertEqual(self.catalog, before)
        self.assertEqual(len(proposals), 10)
        self.assertEqual(len({p['proposal_id'] for p in proposals}), 10)
        source = {i['id']: i for i in self.source_items(self.catalog)}
        self.assertEqual([p['source_item_id'] for p in proposals],
                         ['p8-b6', 'p8-b7', 'p8-b8', 'p8-b9', 'p8-b10', 'p8-b11', 'p8-b16', 'p8-b15', 'p8-b17', 'p8-b18'])
        for index, proposal in enumerate(proposals):
            with self.subTest(item=proposal['source_item_id']):
                item = source[proposal['source_item_id']]
                self.assertEqual(proposal['source_text'], item['text'])
                self.assertEqual(proposal['demo_urls'], item['demoURLs'])
                self.assertEqual(proposal['source_prescription']['text'],
                                 '3 SETS OF 10 REPS EACH EXERCISE' if index < 6 else '2 SETS OF 5-8 REPS EACH EXERCISE')
                self.assertEqual(proposal['evidence_status'], 'prescription_only_not_observed_activity')
                self.assertEqual(proposal['review_state'], 'source_rule_proposal_not_promoted')
                self.assertNotIn('duration_seconds', proposal)
                self.assertNotIn('performed_reps', proposal)

    def test_only_exact_squat_gets_existing_unvalidated_rep_recipe(self):
        proposals = normalize_day_six_items(self.catalog)
        self.assertEqual(proposals[0]['exercise_key'], 'squats')
        self.assertEqual(proposals[0]['measurement'], {'id': 'mediapipe-squat-angle', 'version': 'v1',
                         'capability': 'rep_candidate', 'validation_status': 'unvalidated'})
        for p in proposals[1:]:
            self.assertEqual(p['measurement']['id'], 'session-clock')
            self.assertEqual(p['measurement']['capability'], 'elapsed_only')
        changed = copy.deepcopy(self.catalog)
        item = next(i for i in self.source_items(changed) if i['id'] == 'p8-b6')
        item['text'] = 'Squat jumps'
        proposal = normalize_day_six_items(changed)[0]
        self.assertIsNone(proposal['exercise_key'])
        self.assertEqual(proposal['normalization_status'], 'unknown')
        self.assertEqual(proposal['measurement']['capability'], 'unsupported')
        self.assertEqual(proposal['source_text'], 'Squat jumps')

    def test_missing_duplicate_extra_or_changed_group_fails_coverage(self):
        for mode in ['missing', 'duplicate', 'extra', 'changed_group']:
            changed = copy.deepcopy(self.catalog)
            items = self.source_items(changed)
            if mode == 'missing':
                items.pop()
            elif mode == 'duplicate':
                items.append(copy.deepcopy(items[-1]))
            elif mode == 'extra':
                items.append({'id': 'p8-new', 'text': 'Burpee'})
            else:
                next(i for i in items if i['id'] == 'p8-b3')['text'] = '5 SETS'
            with self.subTest(mode=mode), self.assertRaises(ValueError):
                normalize_day_six_items(changed)

    def test_proposal_identity_covers_catalog_source_item_and_recipe_version(self):
        p = normalize_day_six_items(self.catalog)[0]
        key = {k: p[k] for k in ['catalog_sha256', 'source_block_id', 'source_item_id', 'normalization_version', 'measurement']}
        self.assertEqual(p['proposal_id'], digest(key))
        key['measurement'] = dict(key['measurement'], version='v2')
        self.assertNotEqual(p['proposal_id'], digest(key))
        changed = copy.deepcopy(self.catalog)
        changed['catalogVersion'] += '-candidate'
        self.assertNotEqual(p['proposal_id'], normalize_day_six_items(changed)[0]['proposal_id'])

    def test_separate_idempotent_job_preserves_baseline_and_calls_no_model(self):
        with tempfile.TemporaryDirectory() as folder:
            store = Store(Path(folder) / 'batch.sqlite')
            baseline_id = store.submit_catalog(self.catalog)
            baseline = store.inspect(baseline_id)
            with patch('urllib.request.urlopen', side_effect=AssertionError('No model or other network call permitted')):
                job_id = store.submit_source_items(self.catalog)
                self.assertEqual(store.submit_source_items(self.catalog), job_id)
            self.assertNotEqual(job_id, baseline_id)
            self.assertEqual(store.inspect(baseline_id), baseline)
            job = store.inspect(job_id)[0]
            self.assertEqual(job['state'], 'complete')
            self.assertEqual(len(job['items']), 10)
            for item in job['items']:
                output = json.loads(item['output'])
                self.assertEqual(item['attempts'], 1)
                self.assertFalse(output['inference_performed'])
                self.assertEqual(output['usage']['total_tokens'], 0)
                self.assertIsNone(output['actual_cost_usd'])
                self.assertNotIn('raw_response', output)

    def test_export_records_tool_proposals_once_without_promoting_to_activity_evidence(self):
        with tempfile.TemporaryDirectory() as folder:
            store = Store(Path(folder) / 'batch.sqlite')
            store.submit_source_items(self.catalog)
            outbox = Path(folder) / 'outbox.sqlite'
            self.assertEqual(store.export(outbox), 10)
            # Existing export API counts exportable attempts, including already queued ones.
            self.assertEqual(store.export(outbox), 10)
            with sqlite3.connect(outbox) as db:
                rows = db.execute('SELECT payload FROM events').fetchall()
            self.assertEqual(len(rows), 10)
            for row in rows:
                event = json.loads(row[0])
                self.assertEqual(event['provenance']['origin'], 'source_curriculum')
                stage = event['stages'][0]
                self.assertEqual(stage['name'], 'batch.source_item')
                self.assertEqual(stage['span_type'], 'TOOL')
                self.assertEqual(stage['outputs']['result']['evidence_status'], 'prescription_only_not_observed_activity')


if __name__ == '__main__':
    unittest.main()
