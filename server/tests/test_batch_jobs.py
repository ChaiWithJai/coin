import json
import io
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
from contextlib import redirect_stdout

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from batch_jobs import Store, ModelClient, report_context, exchange_context, main


class Response:
    def __init__(self, content):
        self.raw = {'choices': [{'message': {'content': content}}], 'usage': {'total_tokens': 4}}
    def __enter__(self): return self
    def __exit__(self, *args): pass
    def read(self): return json.dumps(self.raw).encode()


def sample():
    return {'language': 'en', 'round': 1, 'duration_s': 180, 'workout_mode': 'freestyle',
            'drill_id': None, 'exchanges': [
                {'id': i, 'punches': [{'hand': 'lead', 'atMs': i * 1000}], 'resetMs': None}
                for i in range(2)]}


class FakeClient:
    def __init__(self):
        self.calls = []
        self.fail = set()
        self.model = 'fixture-model-v1'

    def identity(self):
        return {'resolved_model': self.model, 'model_sha256': None}

    def run(self, kind, data):
        self.calls.append((kind, data))
        if kind == 'exchange' and data['exchange']['id'] in self.fail:
            raise RuntimeError('fixture model failure')
        return {'result': {'decision': 'review'} if kind == 'exchange' else {'observation': 'fixture'},
                'actual_cost_usd': None, 'duration_ms': 1}


class BatchTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.store = Store(Path(self.temp.name) / 'jobs.sqlite')
        self.client = FakeClient()
        self.provenance = {'origin': 'synthetic', 'source_id': 'fixture-round'}

    def submit(self, **kwargs):
        return self.store.submit(sample(), self.provenance, **kwargs)

    def drain(self):
        for _ in range(10):
            if not self.store.step(self.client):
                break
        else:
            self.fail('Worker did not terminate')

    def test_restart_pause_resume_and_idempotence(self):
        job = self.submit()
        self.assertEqual(job, self.submit())
        self.store.control(job, 'pause')
        self.assertFalse(self.store.step(self.client))
        self.store = Store(self.store.path)
        self.store.control(job, 'resume')
        self.drain()
        result = self.store.inspect(job)[0]
        self.assertEqual(result['state'], 'complete')
        self.assertEqual(len(self.client.calls), 3)
        self.assertFalse(self.store.step(self.client))
        ex = self.client.calls[0][1]
        self.assertEqual(ex['workout_mode'], 'freestyle')
        self.assertIsNone(ex['drill_id'])
        self.assertEqual(ex['source']['origin'], 'synthetic')

    def test_program_source_context_preserved_without_unrelated_faults(self):
        record = sample()
        record.update(language='fr', workout_mode='program', drill_id='probe-combine-angle-v1',
                      source_id='basic-w1-d1', source_title='Squat preparation',
                      source_instructions='12 JUMP SQUATS')
        record['exchanges'][0].update(opener='commit', lateralShift=0, cue='exit_angle')
        record['exchanges'][0]['punches'][0]['rearHandLow'] = True
        job = self.store.submit(record, self.provenance)
        self.store.step(self.client, job_id=job)
        data = self.client.calls[0][1]
        self.assertEqual(data['language'], 'fr')
        self.assertEqual(data['source_instructions'], '12 JUMP SQUATS')
        self.assertEqual(data['assessment_scope'], 'observed_events_only')
        self.assertNotIn('opener', data['exchange'])
        self.assertNotIn('resetMs', data['exchange'])
        self.assertNotIn('lateralShift', data['exchange'])
        self.assertNotIn('rearHandLow', data['exchange']['punches'][0])
        with self.store.db() as db:
            original = json.loads(db.execute('SELECT input FROM jobs WHERE id=?', (job,)).fetchone()[0])
        self.assertEqual(original, record)

    def test_already_queued_v1_item_rebuilds_context_from_original_round(self):
        record = sample()
        record.update(language='fr', source_instructions='Move in all directions')
        job = self.store.submit(record, self.provenance)
        with self.store.db() as db:
            db.execute('UPDATE items SET input=? WHERE job_id=? AND kind=?',
                       (json.dumps({'exchange': {'id': 0, 'opener': 'commit'}, 'workout_mode': 'unknown'}), job, 'exchange'))
        self.store.step(self.client, job_id=job)
        self.assertEqual(self.client.calls[0][1]['language'], 'fr')
        self.assertEqual(self.client.calls[0][1]['source_instructions'], 'Move in all directions')
        self.assertNotIn('opener', self.client.calls[0][1]['exchange'])

    def test_explicit_drill_keeps_candidates_but_free_mode_overrides(self):
        record = sample()
        record.update(workout_mode='drill', drill_id='probe-combine-angle-v1')
        ex = dict(record['exchanges'][0], opener='commit')
        data = exchange_context(record, ex, self.provenance)
        self.assertEqual(data['assessment_scope'], 'assigned_drill_candidates')
        self.assertEqual(data['exchange']['opener'], 'commit')
        record['workout_mode'] = 'freestyle'
        self.assertEqual(exchange_context(record, ex, self.provenance)['assessment_scope'], 'observed_events_only')

    def test_unsupported_cue_proposal_is_review_and_raw_choice_retained(self):
        record = sample()
        data = exchange_context(record, record['exchanges'][0], self.provenance)
        with patch('urllib.request.urlopen', return_value=Response('A')):
            out = ModelClient('http://fixture').run('exchange', data)
        self.assertEqual(out['result']['decision'], 'review')
        self.assertEqual(out['result']['proposed_decision'], 'cue')
        self.assertTrue(out['result']['evidence_gate_applied'])
        self.assertEqual(out['raw_response']['choices'][0]['message']['content'], 'A')

    def test_report_contains_source_context_and_accounts_for_missing_items(self):
        record = sample()
        record.update(source_title='Bag work', source_instructions='Six rounds', source_id='block1')
        context = report_context(record, [{'item_id': 'exchange:0', 'kind': 'exchange', 'state': 'complete',
                                          'output': json.dumps({'result': {'decision': 'cue', 'valid_choice': False}})}])
        self.assertEqual(context['round']['source_instructions'], 'Six rounds')
        self.assertEqual(context['classification_counts']['review'], 1)
        self.assertEqual(context['classification_counts']['pending'], 1)
        self.assertEqual(sum(context['classification_counts'].values()), 2)
        self.assertNotIn('fault_counts', context)

    def test_french_report_rejects_wrong_language_and_unsupported_technique(self):
        record = sample()
        record.update(language='fr', workout_mode='program', source_instructions='Jab and exit')
        context = report_context(record, [])
        proposal = json.dumps({'observation': 'You missed the jab', 'focus': 'Reset the angle',
                               'limitations': 'Your guard is poor'})
        with patch('urllib.request.urlopen', return_value=Response(proposal)):
            out = ModelClient('http://fixture').run('report', context)
        self.assertEqual(out['result']['observation'], '2 échanges et 2 départs de coups repérés.')
        self.assertEqual(out['result']['focus'], 'Continue la consigne de ton programme au prochain round.')
        self.assertIn('Analyse de 2 échanges indisponible', out['result']['limitations'])
        self.assertTrue(out['output_gate']['used_fallback'])
        self.assertEqual(out['raw_response']['choices'][0]['message']['content'], proposal)

    def test_zero_detections_never_claim_inactivity(self):
        record = sample()
        record['exchanges'] = []
        with patch('urllib.request.urlopen', return_value=Response('[]')):
            out = ModelClient('http://fixture').run('report', report_context(record, []))
        self.assertIn('does not establish inactivity', out['result']['limitations'])
        self.assertEqual(out['result']['focus'], 'Choose one focus for your next freestyle round.')
        self.assertTrue(out['output_gate']['used_fallback'])

    def test_one_detected_exchange_uses_singular_english_and_french(self):
        for language, expected in (
            ('fr', '1 échange et 1 départ de coup repérés.'),
            ('en', '1 exchange and 1 punch onset detected.'),
        ):
            record = sample()
            record['language'] = language
            record['exchanges'] = record['exchanges'][:1]
            with self.subTest(language=language), patch('urllib.request.urlopen', return_value=Response('{}')):
                out = ModelClient('http://fixture').run('report', report_context(record, []))
            self.assertEqual(out['result']['observation'], expected)

    def test_job_selector_preserves_older_queued_job_and_cli_result(self):
        first = self.submit(job_id='older')
        selected = self.submit(job_id='selected')
        output = io.StringIO()
        with patch('sys.argv', ['batch_jobs.py', '--db', str(self.store.path), 'work', '--job-id', selected, '--max-items', '3']), \
             patch('batch_jobs.ModelClient', return_value=self.client), redirect_stdout(output):
            main()
        self.assertEqual(json.loads(output.getvalue())['processed_items'], 3)
        self.assertEqual(self.store.inspect(first)[0]['state'], 'pending')
        self.assertTrue(all(i['attempts'] == 0 for i in self.store.inspect(first)[0]['items']))
        self.assertEqual(self.store.result(selected)['report'], {'observation': 'fixture'})
        output = io.StringIO()
        with patch('sys.argv', ['batch_jobs.py', '--db', str(self.store.path), 'result', selected]), redirect_stdout(output):
            main()
        self.assertEqual(json.loads(output.getvalue())['state'], 'complete')
        with self.assertRaises(ValueError):
            self.store.step(self.client, job_id='missing')

    def test_retry_does_not_return_a_stale_report(self):
        job = self.submit()
        self.client.fail = {0}
        self.drain()
        self.assertEqual(self.store.result(job)['state'], 'partial')
        self.assertIsNotNone(self.store.result(job)['report'])
        self.store.control(job, 'retry')
        result = self.store.result(job)
        self.assertEqual(result['report_state'], 'pending')
        self.assertIsNone(result['report'])
        self.assertIsNone(result['report_model'])

    def test_resume_after_last_inflight_item_finished_while_paused(self):
        data = sample()
        data['exchanges'] = []
        job = self.store.submit(data, self.provenance)
        original = self.client.run
        def pausing_client(kind, data):
            self.store.control(job, 'pause')
            return original(kind, data)
        self.client.run = pausing_client
        self.store.step(self.client)
        self.assertEqual(self.store.inspect(job)[0]['state'], 'paused')
        self.store.control(job, 'resume')
        self.assertEqual(self.store.inspect(job)[0]['state'], 'complete')
        self.assertFalse(self.store.step(self.client))

    def test_partial_failure_retry_only_failed_exchange_and_report(self):
        job = self.submit()
        self.client.fail = {0}
        self.drain()
        self.assertEqual(self.store.inspect(job)[0]['state'], 'partial')
        self.assertEqual(self.client.calls[-1][1]['classification_counts']['failed'], 1)
        self.client.fail.clear()
        self.store.control(job, 'retry')
        self.drain()
        self.assertEqual(self.store.inspect(job)[0]['state'], 'complete')
        self.assertEqual([x[1]['exchange']['id'] for x in self.client.calls if x[0] == 'exchange'], [0, 1, 0])
        self.assertEqual(len(self.client.calls), 5)
        with self.store.db() as db:
            self.assertEqual(db.execute("SELECT count(*) FROM attempts WHERE state='failed'").fetchone()[0], 1)

    def test_cache_separates_models_and_id_conflicts(self):
        self.submit(job_id='first')
        self.drain()
        self.submit(job_id='second')
        self.drain()
        self.assertEqual(len(self.client.calls), 3)
        cached = json.loads(self.store.inspect('second')[0]['items'][0]['output'])
        self.assertEqual(cached['usage']['total_tokens'], 0)
        self.assertFalse(cached['inference_performed'])
        self.assertEqual(cached['duration_ms'], 0)
        self.client.model = 'fixture-model-v2'
        self.submit(job_id='third')
        self.drain()
        self.assertEqual(len(self.client.calls), 6)
        changed = sample()
        changed['language'] = 'fr'
        with self.assertRaises(ValueError):
            self.store.submit(changed, self.provenance, 'first')

    def test_single_worker_lease_and_crash_recovery(self):
        self.submit()
        claimed = self.store._claim('first-owner', 100)
        self.assertIsNotNone(claimed)
        self.assertIsNone(self.store._claim('second-owner', 101))
        recovered = self.store._claim('second-owner', 221)
        self.assertEqual(recovered['item_id'], claimed['item_id'])

    def test_export_is_deduplicated_and_preserves_failed_attempts(self):
        job = self.submit()
        self.client.fail = {0}
        self.drain()
        outbox = Path(self.temp.name) / 'events.sqlite'
        self.store.export(outbox)
        self.client.fail.clear()
        self.store.control(job, 'retry')
        self.drain()
        self.assertEqual(self.store.export(outbox), 5)
        self.store.export(outbox)
        from telemetry import Outbox
        self.assertEqual(Outbox(outbox).counts(), {'pending': 5})

    def test_empty_round_and_input_limits(self):
        data = sample()
        data['exchanges'] = []
        self.store.submit(data, self.provenance)
        self.drain()
        self.assertEqual(self.client.calls[0][1]['exchange_count'], 0)
        data['exchanges'] = [{'id': 0, 'punches': []}]
        with self.assertRaises(ValueError):
            self.store.submit(data, self.provenance)

    def test_catalog_deduplicates_text_and_preserves_prescription(self):
        block = {'id': 'a', 'sourceText': 'BAG WORK: 4 rounds of 2 minutes.', 'kind': 'boxing',
                 'durationSeconds': 120, 'rounds': 4, 'restSeconds': 30, 'reps': None}
        catalog = {'sourceURL': 'https://boxing.dharmicdata.org', 'catalogVersion': 'fixture',
                   'workouts': [{'id': 'day1', 'sourceSHA256': 'fixturehash',
                                 'blocks': [block, dict(block, id='b')]}]}
        before = json.dumps(catalog, sort_keys=True)
        job = self.store.submit_catalog(catalog)
        self.assertEqual(job, self.store.submit_catalog(catalog))
        self.drain()
        self.assertEqual(len(self.client.calls), 1)
        self.assertEqual(self.client.calls[0][0], 'workout')
        self.assertEqual(json.dumps(catalog, sort_keys=True), before)
        self.assertEqual(self.store.inspect(job)[0]['state'], 'complete')

    def test_catalog_explicit_exercise_uses_source_without_model(self):
        with patch('urllib.request.urlopen', side_effect=AssertionError('No model needed')):
            result = ModelClient('http://fixture').run('workout', {'block': {'sourceText': '12 JUMP SQUATS', 'kind': 'exercise'}})
        self.assertEqual(result['result']['activity'], 'strength')
        self.assertEqual(result['result']['cue_id'], 'follow_source')
        self.assertFalse(result['inference_performed'])
        self.assertEqual(result['usage']['total_tokens'], 0)

    def test_catalog_unsupported_model_choice_is_unknown(self):
        raw = {'choices': [{'message': {'content': 'C'}}]}
        class Response:
            def __enter__(self): return self
            def __exit__(self, *args): pass
            def read(self): return json.dumps(raw).encode()
        with patch('urllib.request.urlopen', return_value=Response()):
            result = ModelClient('http://fixture').run('workout', {'block': {'sourceText': 'STANCE DRILL', 'kind': 'boxing'}})
        self.assertEqual(result['result']['activity'], 'unknown')
        self.assertEqual(result['result']['phase'], 'unspecified')
        self.assertEqual(result['result']['cue_id'], 'follow_source')

    def test_source_typo_preserved_in_supported_model_annotation(self):
        raw = {'choices': [{'message': {'content': 'A'}}]}
        class Response:
            def __enter__(self): return self
            def __exit__(self, *args): pass
            def read(self): return json.dumps(raw).encode()
        source = 'MOVE AND THROW PUCNHES WITH A STEP'
        with patch('urllib.request.urlopen', return_value=Response()):
            result = ModelClient('http://fixture').run('workout', {'block': {'sourceText': source, 'kind': 'boxing'}})
        self.assertEqual(result['result']['activity'], 'shadowboxing')
        self.assertEqual(result['result']['evidence_quote'], 'PUCNH')
        self.assertIn(result['result']['evidence_quote'], source)

    def test_invalid_choice_abstains_without_invented_confidence(self):
        raw = {'choices': [{'message': {'content': 'X'}, 'logprobs': None}],
               'usage': {'prompt_tokens': 20, 'completion_tokens': 1}}
        class Response:
            def __enter__(self): return self
            def __exit__(self, *args): pass
            def read(self): return json.dumps(raw).encode()
        with patch('urllib.request.urlopen', return_value=Response()):
            result = ModelClient('http://fixture').run('exchange', {'exchange': {}, 'drill_id': None})
        self.assertEqual(result['result']['decision'], 'review')
        self.assertFalse(result['result']['valid_choice'])
        self.assertEqual(result['result']['unreported_probability_mass'], 1)
        self.assertIsNone(result['actual_cost_usd'])
        self.assertEqual(result['usage']['prompt_tokens'], 20)


if __name__ == '__main__':
    unittest.main()
