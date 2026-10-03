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

    def test_pose_window_trace_keeps_runtime_activity_identity(self):
        import json
        activity_id=uuid.uuid4()
        body=self.service.PoseWindow(request_id=uuid.uuid4(),session_id=self.session_id,
            block_id=self.block_id,activity_instance_id=activity_id,runtime_origin='synthetic',sequence=1,sampled_at_ms=1000,
            language='fr',landmark_count=33,visible_landmark_count=20,
            framing_ready=False,source_version='mediapipe-pose-full-v1')
        self.service.pose_window(body)
        with self.service.OUTBOX.connect() as db:
            payload=json.loads(db.execute('SELECT payload FROM events').fetchone()[0])
        self.assertEqual(payload['activity_instance_id'],str(activity_id))
        self.assertEqual(payload['origin'],'synthetic')
        self.assertEqual(payload['stages'][0]['inputs']['activity_instance_id'],str(activity_id))
        self.assertEqual(payload['decision']['action'],'silence')

    def test_activity_lineage_is_kept_without_claiming_recognition(self):
        selected=dict(instance_id=uuid.uuid4(),block_id=self.block_id,source_block_id='basic-w1-d6-p8-s1-1',
                      source_item_id='p8-b6',exercise_key='custom',selection_provenance='user_selected',
                      measurement=dict(id='session-clock',version='v1',capability='elapsed_only',validation_status='not_applicable'),
                      selected_at_ms=2000)
        self.service.workout_completion(self.receipt(activity_instances=[selected]))
        with self.service.OUTBOX.connect() as db:
            row=db.execute('SELECT payload FROM events').fetchone()
        import json
        output=json.loads(row[0])['stages'][0]['outputs']['activity_instances'][0]
        self.assertEqual(output['exercise_key'],'custom')
        self.assertEqual(output['measurement']['capability'],'elapsed_only')
        self.assertNotIn('custom_name',output)

    def test_runtime_measurement_contract_is_preserved_without_verification_claim(self):
        selected=self.activity(measurement=dict(id='mediapipe-squat-angle',version='v1',
            capability='rep_candidate',validation_status='unvalidated',
            landmark_groups=[['left_hip','left_knee','left_ankle'],
                             ['right_hip','right_knee','right_ankle']],visibility_rule='any_complete_group',
            observation_unit='rep_candidate'))
        self.service.workout_completion(self.receipt(activity_instances=[selected]))
        with self.service.OUTBOX.connect() as db:
            row=db.execute('SELECT payload FROM events').fetchone()
        import json
        measurement=json.loads(row[0])['stages'][0]['outputs']['activity_instances'][0]['measurement']
        self.assertEqual(measurement['landmark_groups'],selected['measurement']['landmark_groups'])
        self.assertEqual(measurement['visibility_rule'],'any_complete_group')
        self.assertEqual(measurement['observation_unit'],'rep_candidate')
        self.assertEqual(measurement['validation_status'],'unvalidated')

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

    def activity(self, **changes):
        body=dict(instance_id=uuid.uuid4(),block_id=self.block_id,exercise_key='squats',
                  selection_provenance='user_selected',measurement=dict(id='mediapipe-squat-angle',version='v1',
                  capability='rep_candidate',validation_status='unvalidated'))
        body.update(changes)
        return body

    def interval(self, instance, start, end, **changes):
        body=dict(interval_id=uuid.uuid4(),block_id=self.block_id,activity_instance_id=instance['instance_id'],
                  start_elapsed_seconds=start,end_elapsed_seconds=end,elapsed_seconds=end-start,
                  exit_reason='choice_changed',closed_at_ms=50000,baseline_only=False,
                  evidence='workout_timer_not_verified_activity')
        body.update(changes)
        return body

    def test_interval_lineage_retains_prior_choice_and_retry_is_idempotent(self):
        import json
        first=self.activity()
        second=self.activity(exercise_key='bench_press',measurement=dict(id='session-clock',version='v1',
                             capability='elapsed_only',validation_status='not_applicable'))
        body=self.receipt(activity_instances=[first,second],activity_intervals=[self.interval(first,0,20),
                         self.interval(second,20,35,exit_reason='session_finished')])
        self.assertEqual(self.service.workout_completion(body),self.service.workout_completion(body))
        with self.service.OUTBOX.connect() as db:
            rows=db.execute('SELECT payload FROM events').fetchall()
        self.assertEqual(len(rows),1)
        intervals=json.loads(rows[0][0])['stages'][0]['outputs']['activity_intervals']
        self.assertEqual([x['elapsed_seconds'] for x in intervals],[20,15])
        self.assertEqual(intervals[0]['activity_instance_id'],str(first['instance_id']))
        self.assertTrue(all(x['evidence']=='workout_timer_not_verified_activity' for x in intervals))
        self.assertNotIn('performed_reps',intervals[0])

    def test_interval_invalid_identity_overlap_duration_and_unmarked_baseline_rejected(self):
        from fastapi import HTTPException
        instance=self.activity()
        first=self.interval(instance,0,20)
        cases=[
            [self.interval(instance,0,10,activity_instance_id=uuid.uuid4())],
            [self.interval(instance,0,10,preparation_index=1)],
            [first,self.interval(instance,19,25)],
            [first,dict(first)],
            [self.interval(instance,0,20,elapsed_seconds=25)],
            [self.interval(instance,20,25)],
            [self.interval(instance,0,0)],
            [self.interval(instance,0,20,baseline_only=True)],
            [first,self.interval(instance,20,20,baseline_only=True)],
        ]
        for intervals in cases:
            with self.subTest(intervals=intervals),self.assertRaises(HTTPException) as failure:
                self.service.workout_completion(self.receipt(activity_instances=[instance],activity_intervals=intervals))
            self.assertEqual(failure.exception.status_code,422)
        self.assertEqual(self.service.OUTBOX.counts(),{})

    def test_legacy_baseline_excludes_old_elapsed_and_preparation_slots_are_independent(self):
        import json
        first=self.activity(preparation_index=0)
        second=self.activity(preparation_index=1)
        intervals=[self.interval(first,40,40,preparation_index=0,baseline_only=True),
                   self.interval(first,40,45,preparation_index=0),
                   self.interval(second,0,10,preparation_index=1)]
        self.service.workout_completion(self.receipt(activity_instances=[first,second],activity_intervals=intervals))
        with self.service.OUTBOX.connect() as db:
            row=db.execute('SELECT payload FROM events').fetchone()
        saved=json.loads(row[0])['stages'][0]['outputs']['activity_intervals']
        self.assertEqual([x['elapsed_seconds'] for x in saved],[0,5,10])

    def test_old_completion_retry_does_not_gain_optional_interval_field(self):
        import json
        body=self.receipt()
        self.service.workout_completion(body)
        with self.service.OUTBOX.connect() as db:
            original=db.execute('SELECT payload FROM events').fetchone()[0]
        self.assertNotIn('activity_intervals',json.loads(original)['stages'][0]['outputs'])
        self.service.workout_completion(body)
        with self.service.OUTBOX.connect() as db:
            retried=db.execute('SELECT payload FROM events').fetchone()[0]
        self.assertEqual(original,retried)

    def test_interval_payload_bounds(self):
        from pydantic import ValidationError
        instance=self.activity()
        for interval in (self.interval(instance,0,86401),self.interval(instance,-1,1),
                         self.interval(instance,0,1,evidence='performed_exercise')):
            with self.assertRaises(ValidationError):
                self.receipt(activity_instances=[instance],activity_intervals=[interval])
