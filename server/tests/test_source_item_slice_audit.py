import json
import sqlite3
import sys
import tempfile
import unittest
from contextlib import closing
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from batch_jobs import Store, catalog_source_item_manifest
from source_item_slice_audit import audit_source_item_slice


def catalog():
    return {
        'catalogVersion': 'slice-fixture-v1',
        'sourceURL': 'https://boxing.example.test',
        'workouts': [{
            'id': 'day', 'sourceSHA256': 'a' * 64,
            'blocks': [
                {'id': 'virtual', 'kind': 'boxing',
                 'sourceText': 'VIRUAL SPARRING\nSINGLE PUNCHES',
                 'sourceItems': [{'id': 'virtual-item', 'text': 'VIRUAL SPARRING'}]},
                {'id': 'bag', 'kind': 'boxing',
                 'sourceText': 'BAG WORK\n3 SECOND SPRINTS\n10 PUSH-UPS AND 10 SQUATS',
                 'sourceItems': [
                     {'id': 'conditioning', 'text': '3 SECOND SPRINTS'},
                     {'id': 'strength', 'text': '10 PUSH-UPS AND 10 SQUATS'},
                 ]},
                {'id': 'model', 'kind': 'exercise',
                 'sourceText': 'ALPHA MOVEMENT\nBETA MOVEMENT',
                 'sourceItems': [
                     {'id': 'alpha', 'text': 'ALPHA MOVEMENT'},
                     {'id': 'beta', 'text': 'BETA MOVEMENT'},
                 ]},
            ],
        }],
    }


class SourceItemSliceAuditTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.path = Path(self.temp.name) / 'batch.sqlite'
        self.store = Store(self.path)
        self.catalog = catalog()
        self.job = self.store.submit_source_items(self.catalog)
        self.proposals = catalog_source_item_manifest(self.catalog)[1]
        with closing(sqlite3.connect(self.path)) as db:
            self.baseline = db.execute(
                "SELECT count(*) FROM items WHERE job_id=? AND state='complete'",
                (self.job,)).fetchone()[0]

    def _complete_pending(self):
        pending = [p for p in self.proposals
                   if p['source_item_id'] in ('alpha', 'beta')]
        with closing(sqlite3.connect(self.path)) as db:
            for index, proposal in enumerate(pending):
                result = dict(proposal, activity='mobility',
                              evidence_quote=proposal['source_text'],
                              annotation_origin='model_choice_with_source_support',
                              review_state='model_proposal_not_promoted',
                              runtime_eligible=False)
                cached = index == 1
                output = {
                    'result': result,
                    'cache_hit': cached,
                    'inference_performed': not cached,
                    'usage': ({'prompt_tokens': 0, 'completion_tokens': 0,
                               'total_tokens': 0} if cached else
                              {'prompt_tokens': 10, 'completion_tokens': 1,
                               'total_tokens': 11}),
                    'actual_cost_usd': None,
                    'estimated_cost_usd': None if cached else 0.002,
                }
                if cached:
                    output['cache_materialization'] = 'model_decision_only_current_source_identity'
                item_id = 'source-item:' + proposal['proposal_id']
                body = json.dumps(output, sort_keys=True, separators=(',', ':'))
                db.execute("""UPDATE items SET state='complete',attempts=1,output=?,model=?
                              WHERE job_id=? AND item_id=?""",
                           (body, '{}', self.job, item_id))
                db.execute('INSERT INTO attempts VALUES(?,?,?,?,?,?,?)',
                           (self.job, item_id, 1, 'complete', body, None, '{}'))
            db.execute("UPDATE jobs SET state='paused' WHERE id=?", (self.job,))
            db.commit()

    def _fixture(self):
        proposal = next(p for p in self.proposals
                        if p['source_item_id'] == 'conditioning')
        path = Path(self.temp.name) / 'analyst.json'
        path.write_text(json.dumps({'corrections': [{
            # Proposal IDs include normalization_version. This deliberately
            # represents an analyst fixture from an earlier candidate job.
            'proposal_id': 'f' * 64,
            'source_block_id': proposal['source_block_id'],
            'source_item_id': proposal['source_item_id'],
            'exact_source_text': proposal['source_text'],
            'proposed_activity': 'conditioning',
        }]}))
        return path

    def test_reports_exact_new_slice_usage_cost_and_regression_sentinels(self):
        self._complete_pending()
        report = audit_source_item_slice(
            self.path, self.job, self.baseline, expected_size=2,
            analyst_fixture=self._fixture())
        self.assertTrue(report['passed'], report['issues'])
        self.assertEqual(report['queue']['complete'], self.baseline + 2)
        self.assertEqual(report['queue']['pending'], 0)
        self.assertEqual(report['slice']['processed_items'], 2)
        self.assertEqual(report['slice']['inference_calls'], 1)
        self.assertEqual(report['slice']['cache_materializations'], 1)
        self.assertEqual(report['slice']['deterministic_results'], 0)
        self.assertEqual(report['slice']['usage']['total_tokens'], 11)
        self.assertEqual(report['slice']['costs']['actual_cost_usd'], {
            'null_count': 2, 'non_null_count': 0, 'sum_usd': None,
            'invalid_count': 0})
        self.assertEqual(report['slice']['costs']['estimated_cost_usd']['null_count'], 1)
        self.assertEqual(report['slice']['costs']['estimated_cost_usd']['non_null_count'], 1)
        self.assertEqual(report['regression_sentinels']['analyst_corrections']['passed'], 1)
        fixture = report['regression_sentinels']['analyst_corrections']['items'][0]
        self.assertEqual(fixture['resolution'], 'stable_source_identity')
        self.assertNotIn('f' * 64, fixture['resolved_item_id'])
        self.assertEqual(report['regression_sentinels']['virtual_or_virual_sparring']['passed'], 1)
        self.assertEqual(report['regression_sentinels']['explicit_child_modality']['passed'], 2)
        self.assertFalse(report['runtime_eligibility']['promotion_performed'])

    def test_detects_slice_identity_quote_runtime_and_fixture_regressions(self):
        self._complete_pending()
        with closing(sqlite3.connect(self.path)) as db:
            item_id, raw = db.execute(
                "SELECT item_id,output FROM items WHERE job_id=? AND input LIKE '%ALPHA MOVEMENT%' AND state='complete'",
                (self.job,)).fetchone()
            output = json.loads(raw)
            output['result']['source_item_id'] = 'wrong'
            output['result']['evidence_quote'] = 'invented quote'
            output['result']['runtime_eligible'] = True
            db.execute('UPDATE items SET output=? WHERE job_id=? AND item_id=?',
                       (json.dumps(output), self.job, item_id))
            # The analyst fixture sentinel is population-level, including
            # deterministic items completed before the baseline.
            target = next(p for p in self.proposals
                          if p['source_item_id'] == 'conditioning')
            target_id = 'source-item:' + target['proposal_id']
            target_raw = db.execute('SELECT output FROM items WHERE job_id=? AND item_id=?',
                                    (self.job, target_id)).fetchone()[0]
            target_output = json.loads(target_raw)
            target_output['result']['activity'] = 'bag_work'
            db.execute('UPDATE items SET output=? WHERE job_id=? AND item_id=?',
                       (json.dumps(target_output), self.job, target_id))
            db.commit()
        report = audit_source_item_slice(
            self.path, self.job, self.baseline, expected_size=2,
            analyst_fixture=self._fixture())
        self.assertFalse(report['passed'])
        codes = {issue['code'] for issue in report['issues']}
        self.assertIn('source_identity_mismatch', codes)
        self.assertIn('known_result_without_exact_source_quote', codes)
        self.assertIn('runtime_eligible_not_false', codes)
        self.assertIn('analyst_fixture_mismatch', codes)
        self.assertIn('explicit_child_modality_regression', codes)

    def test_fixture_completed_before_baseline_is_a_population_sentinel(self):
        # The correction target is deterministic and complete before the
        # baseline. Only alpha/beta belong to the newly completed slice.
        self._complete_pending()
        report = audit_source_item_slice(
            self.path, self.job, self.baseline, expected_size=2,
            analyst_fixture=self._fixture())
        sentinel = report['regression_sentinels']['analyst_corrections']
        self.assertEqual(sentinel['checked'], 1)
        self.assertEqual(sentinel['passed'], 1)
        self.assertEqual(sentinel['items'][0]['actual'], 'conditioning')
        self.assertNotIn(sentinel['items'][0]['resolved_item_id'],
                         report['slice']['item_ids'])

    def test_fails_if_worker_has_not_reached_the_bounded_size(self):
        report = audit_source_item_slice(self.path, self.job, self.baseline,
                                         expected_size=2)
        self.assertFalse(report['passed'])
        self.assertEqual(report['slice']['processed_items'], 0)
        self.assertIn('slice_size_mismatch',
                      {issue['code'] for issue in report['issues']})


if __name__ == '__main__':
    unittest.main()
