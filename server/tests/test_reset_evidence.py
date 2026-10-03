"""Reset absence requires temporal visibility, never a missing legacy field."""
import copy
import importlib.util
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

SERVER = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SERVER))
import round_harness as harness


class ResetEvidenceTests(unittest.TestCase):
    def exchange(self, **changes):
        value = {'id': 1, 'startMs': 100, 'endMs': 100, 'opener': 'probe',
                 'resetMs': None, 'lateralShift': 0, 'cue': None,
                 'punches': [{'hand': 'lead', 'atMs': 100, 'peakSpeed': 5, 'rearHandLow': False}]}
        value.update(changes)
        return value

    def evidence(self, **changes):
        value = {'version': 'pose-reset-observability-v1', 'status': 'not_detected',
                 'observedDurationMs': 1600, 'windowDurationMs': 1600}
        value.update(changes)
        return value

    def test_legacy_null_and_incomplete_evidence_never_become_reset_fault(self):
        for evidence in [None, self.evidence(status='unobservable'), self.evidence(observedDurationMs=1200),
                         self.evidence(version='unknown'), self.evidence(windowDurationMs=0),
                         self.evidence(status='observed')]:
            with self.subTest(evidence=evidence):
                ex = self.exchange(resetEvidence=evidence)
                self.assertEqual(harness.reset_status(ex), 'unobservable')
                self.assertNotIn('no_reset', harness.describe(ex)[1])
        self.assertEqual(harness.reset_status(self.exchange(resetMs=100)), 'observed')

    def test_complete_window_can_report_candidate_without_claiming_certainty(self):
        ex = self.exchange(resetEvidence=self.evidence())
        self.assertIn('no_reset', harness.describe(ex)[1])
        summary = {'exchanges': [ex, self.exchange(id=2)], 'round': 1, 'duration_s': 180}
        raw = {'model': 'fixture-model', 'choices': [{'message': {'content': '{"interpretation":"fixture"}'}}]}
        with patch.object(harness, '_post', return_value=raw) as call:
            out, facts, _ = harness.report(summary, [], 'en')
        self.assertEqual(facts['reset_evidence_counts'], {'observed': 0, 'not_detected': 1, 'unobservable': 1})
        self.assertEqual(facts['reset_evaluable_exchanges'], 1)
        self.assertEqual(facts['reset_rate'], 0)
        self.assertIn('not detected', out['observation'])
        self.assertIn('not proof', call.call_args.args[1]['messages'][0]['content'])

    def test_unknown_only_uses_localized_review_without_invented_correction(self):
        for language in ('fr', 'en'):
            with patch.object(harness, '_post', side_effect=AssertionError('no report inference')):
                out, facts, stage = harness.report({'exchanges': [self.exchange()], 'round': 1, 'duration_s': 180}, [], language)
            self.assertEqual(out['drill_id'], 'review_evidence')
            self.assertIsNone(facts['reset_rate'])
            self.assertIsNone(facts['main_issue'])
            self.assertFalse(stage['outputs']['inference_performed'])
            self.assertIn('non évaluables' if language == 'fr' else 'could not be assessed', out['observation'])

    def test_service_preserves_new_evidence_without_changing_legacy_payload(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root / 'token').write_text('test-only-' + 'x' * 64)
            with patch.dict(os.environ, {'COIN_TOKEN_FILE': str(root / 'token'), 'COIN_STATE_DIR': str(root / 'state')}):
                spec = importlib.util.spec_from_file_location('coin_reset_test', SERVER / 'service.py')
                service = importlib.util.module_from_spec(spec)
                spec.loader.exec_module(service)
            legacy = self.exchange()
            self.assertEqual(service.Exchange(**legacy).model_dump(), legacy)
            self.assertEqual(json.loads(service.Exchange(**legacy).model_dump_json()), legacy)
            current = self.exchange(resetEvidence=self.evidence())
            self.assertEqual(service.Exchange(**current).model_dump(), current)


if __name__ == '__main__':
    unittest.main()
