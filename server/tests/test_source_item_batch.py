import copy
import json
import sqlite3
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from batch_jobs import Store, catalog_source_item_manifest, digest, normalize_day_six_items


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

    def test_catalog_manifest_pins_all_source_items_and_stable_ids(self):
        manifest, proposals = catalog_source_item_manifest(self.catalog)
        self.assertEqual(manifest['source_item_count'], 1773)
        self.assertEqual(len(proposals), 1773)
        self.assertEqual(len({p['proposal_id'] for p in proposals}), 1773)
        self.assertEqual(manifest['catalog_sha256'], digest(self.catalog))
        self.assertEqual(manifest['source_sha256'], sorted({w['sourceSHA256'] for w in self.catalog['workouts']}))
        self.assertTrue(all(p['catalog_sha256'] == manifest['catalog_sha256'] for p in proposals))
        self.assertTrue(all(p['runtime_eligible'] is False for p in proposals))
        self.assertEqual(catalog_source_item_manifest(self.catalog), (manifest, proposals))

    def test_separate_idempotent_job_is_atomic_and_queues_only_fallbacks(self):
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
            self.assertEqual(job['state'], 'pending')
            self.assertEqual(len(job['items']), 1773)
            complete = [item for item in job['items'] if item['state'] == 'complete']
            pending = [item for item in job['items'] if item['state'] == 'pending']
            self.assertGreater(len(complete), 0)
            self.assertGreater(len(pending), 0)
            for item in complete:
                output = json.loads(item['output'])
                self.assertEqual(item['attempts'], 1)
                self.assertFalse(output['inference_performed'])
                self.assertEqual(output['usage']['total_tokens'], 0)
                self.assertIsNone(output['actual_cost_usd'])
                self.assertNotIn('raw_response', output)
            self.assertTrue(all(item['attempts'] == 0 and item['output'] is None for item in pending))

            malformed = copy.deepcopy(self.catalog)
            malformed['workouts'][-1]['blocks'][-1]['sourceItems'][-1]['text'] = ''
            before = store.inspect()
            with self.assertRaises(ValueError):
                store.submit_source_items(malformed)
            self.assertEqual(store.inspect(), before)

    def test_export_records_tool_proposals_once_without_promoting_to_activity_evidence(self):
        with tempfile.TemporaryDirectory() as folder:
            store = Store(Path(folder) / 'batch.sqlite')
            job_id = store.submit_source_items(self.catalog)
            outbox = Path(folder) / 'outbox.sqlite'
            completed = sum(i['state'] == 'complete' for i in store.inspect(job_id)[0]['items'])
            self.assertEqual(store.export(outbox), completed)
            # Existing export API counts exportable attempts, including already queued ones.
            self.assertEqual(store.export(outbox), completed)
            with sqlite3.connect(outbox) as db:
                rows = db.execute('SELECT payload FROM events').fetchall()
            self.assertEqual(len(rows), completed)
            for row in rows:
                event = json.loads(row[0])
                self.assertEqual(event['provenance']['origin'], 'source_curriculum')
                stages = {stage['name']: stage for stage in event['stages']}
                self.assertEqual(list(stages), [
                    'source_item.normalization', 'source_item.gate_decision',
                    'source_item.human_review', 'source_item.promotion_decision'])
                self.assertNotIn('source_item.model_inference', stages)
                self.assertEqual(stages['source_item.normalization']['span_type'], 'TOOL')
                gate = stages['source_item.gate_decision']['outputs']
                self.assertEqual(gate['decision'], 'requires_human_review')
                self.assertEqual(gate['evidence_status'], 'source_prescription_not_observed_activity')
                self.assertEqual(stages['source_item.human_review']['outputs']['state'], 'not_performed')
                self.assertEqual(stages['source_item.promotion_decision']['outputs'], {
                    'decision': 'not_promoted', 'reason': 'human_review_not_performed'})

    def test_source_item_export_adds_model_span_only_when_inference_was_recorded(self):
        from batch_jobs import source_item_export_stages
        base = {'result': {'source_item_id': 'one', 'normalization_status': 'candidate',
                           'evidence_status': 'source_only', 'review_state': 'model_proposal'},
                'duration_ms': 12, 'usage': {'total_tokens': 7}}
        without = source_item_export_stages(dict(base, inference_performed=False), 'job', 'item', {})
        self.assertNotIn('source_item.model_inference', [stage['name'] for stage in without])
        with_model = source_item_export_stages(dict(base, inference_performed=True), 'job', 'item', {'model': 'fixture'})
        inference = next(stage for stage in with_model if stage['name'] == 'source_item.model_inference')
        self.assertEqual(inference['span_type'], 'LLM')
        self.assertTrue(inference['outputs']['inference_performed'])
        self.assertEqual(inference['outputs']['model_versions'], {'model': 'fixture'})

    def test_export_writes_each_lifecycle_stage_from_a_stored_attempt(self):
        with tempfile.TemporaryDirectory() as folder:
            store = Store(Path(folder) / 'batch.sqlite')
            proposal = {'proposal_id': 'proposal', 'source_item_id': 'source',
                        'normalization_version': 'fixture-v1',
                        'normalization_status': 'candidate',
                        'evidence_status': 'source_only',
                        'review_state': 'model_proposal_not_promoted'}
            output = {'result': proposal, 'inference_performed': True,
                      'usage': {'total_tokens': 3}, 'duration_ms': 8}
            with store.db() as db:
                db.execute('INSERT INTO jobs VALUES(?,?,?,?,?)',
                           ('job', '{}', json.dumps({'origin': 'source_curriculum',
                                                    'source_id': 'fixture'}), 'complete', 0))
                db.execute('INSERT INTO items(job_id,item_id,kind,input,state,attempts,output) VALUES(?,?,?,?,?,?,?)',
                           ('job', 'source-item:proposal', 'source_item', '{}', 'complete', 1,
                            json.dumps(output)))
                db.execute('INSERT INTO attempts VALUES(?,?,?,?,?,?,?)',
                           ('job', 'source-item:proposal', 1, 'complete', json.dumps(output), None,
                            json.dumps({'model': 'fixture'})))
            outbox = Path(folder) / 'outbox.sqlite'
            self.assertEqual(store.export(outbox), 1)
            with sqlite3.connect(outbox) as db:
                event = json.loads(db.execute('SELECT payload FROM events').fetchone()[0])
            names = [stage['name'] for stage in event['stages']]
            self.assertEqual(names, ['source_item.normalization', 'source_item.model_inference',
                                     'source_item.gate_decision', 'source_item.human_review',
                                     'source_item.promotion_decision'])
            self.assertEqual(event['stages'][-2]['outputs']['state'], 'not_performed')
            self.assertEqual(event['stages'][-1]['outputs']['decision'], 'not_promoted')


if __name__ == '__main__':
    unittest.main()
