"""A workout can be recorded without any recognized boxing exchanges."""
import importlib.util
import os
import sys
import tempfile
import unittest
import uuid
from pathlib import Path
from unittest.mock import patch

SERVER=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(SERVER))

class WorkoutCompletionTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        root=Path(self.temp.name)
        (root/'token').write_text('test-only-'+('x'*64))
        with patch.dict(os.environ,{'COIN_TOKEN_FILE':str(root/'token'),'COIN_STATE_DIR':str(root/'state')}):
            spec=importlib.util.spec_from_file_location('coin_completion_'+uuid.uuid4().hex,SERVER/'service.py')
            self.service=importlib.util.module_from_spec(spec)
            spec.loader.exec_module(self.service)
        self.request_id=uuid.uuid4()
        self.session_id=uuid.uuid4()
        self.block_id=uuid.uuid4()

    def receipt(self,**changes):
        body=dict(schema_version='workout-completion-v1',request_id=self.request_id,
                  session_id=self.session_id,source_version='catalog-sha',runtime_origin='simulator',
                  started_at_ms=1000,ended_at_ms=61000,
                  completion_evidence='session_ended_not_verified_adherence',
                  pose_sharing_enabled=False,
                  blocks=[dict(block_id=self.block_id,source_block_id='basic-w1-d6-p8-s1-1',
                               source_item_id='p8-b6',completion_sources=['manual_completed'],
                               segments=[dict(segment_id=uuid.uuid4(),elapsed_seconds=60,planned_seconds=0,
                                              is_rest=False,exit_reason='manual_completed')],cue_requests=[],
                               observed_pose_samples=None,observed_visible_pose_samples=None,
                               observed_rep_candidates=None)])
        body.update(changes)
        return self.service.WorkoutCompletion(**body)

    def test_strength_only_receipt_is_durable_and_idempotent_without_model_call(self):
        body=self.receipt()
        with patch.object(self.service.round_harness,'run',side_effect=AssertionError('no inference')):
            first=self.service.workout_completion(body)
            second=self.service.workout_completion(body)
        self.assertEqual(first,second)
        self.assertEqual(first,{'event_id':str(self.request_id),'accepted':True})
        with self.service.OUTBOX.connect() as db:
            rows=db.execute('SELECT payload FROM events').fetchall()
        self.assertEqual(len(rows),1)
        import json
        payload=json.loads(rows[0][0])
        self.assertEqual(payload['origin'],'simulator')
        self.assertEqual(payload['captured_at'],61)
        self.assertNotIn('received_at',payload)
        self.assertEqual(payload['stages'][0]['inputs']['source_version'],'catalog-sha')
        self.assertEqual(payload['decision']['evidence'],'session_ended_not_verified_adherence')
        self.assertEqual(payload['stages'][0]['outputs']['blocks'][0]['source_item_id'],'p8-b6')
        self.assertEqual(payload['stages'][0]['outputs']['blocks'][0]['segments'][0]['exit_reason'],'manual_completed')

    def test_pose_counts_require_explicit_sharing(self):
        from fastapi import HTTPException
        blocks=self.receipt().blocks
        blocks[0].observed_pose_samples=4
        with self.assertRaises(HTTPException) as failure:
            self.service.workout_completion(self.receipt(blocks=blocks))
        self.assertEqual(failure.exception.status_code,422)
        self.assertEqual(self.service.OUTBOX.counts(),{})

    def test_conflicting_retry_cannot_replace_receipt(self):
        from fastapi import HTTPException
        body=self.receipt()
        self.service.workout_completion(body)
        with self.assertRaises(HTTPException) as failure:
            self.service.workout_completion(body.model_copy(update={'runtime_origin':'physical_device'}))
        self.assertEqual(failure.exception.status_code,409)

    def test_ended_time_and_completion_sources_are_bounded(self):
        from fastapi import HTTPException
        for body in (self.receipt(ended_at_ms=0),
                     self.receipt(blocks=[self.receipt().blocks[0].model_copy(update={'completion_sources':['verified_squat']})])):
            with self.assertRaises(HTTPException) as failure:self.service.workout_completion(body)
            self.assertEqual(failure.exception.status_code,422)
