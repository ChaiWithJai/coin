"""Live reports durably schedule offline work without executing a batch model."""
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
from batch_jobs import Store

class ServiceBatchTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        root=Path(self.temp.name)
        (root/'token').write_text('test-only-'+('x'*64))
        with patch.dict(os.environ,{'COIN_TOKEN_FILE':str(root/'token'),'COIN_STATE_DIR':str(root/'state')}):
            spec=importlib.util.spec_from_file_location('coin_service_test_'+uuid.uuid4().hex,SERVER/'service.py')
            self.service=importlib.util.module_from_spec(spec)
            spec.loader.exec_module(self.service)
        self.body=self.service.RoundSummary(request_id=uuid.uuid4(),session_id=uuid.uuid4(),language='en',
            round=1,duration_s=120,workout_mode='program',source_id='basic-w1-d1-p3-s3-1',
            source_title='FRONTAL STANCE DRILL',source_instructions='4 ROUNDS OF 2 MINUTES',
            exchanges=[{'id':1,'startMs':100,'endMs':300,'opener':'probe','lateralShift':0,
             'punches':[{'hand':'lead','atMs':100,'peakSpeed':5,'rearHandLow':False}]}])
        self.model=patch.object(self.service.round_harness,'run',return_value=({'constraint':'Follow source'},[],{}))
        self.mock_model=self.model.start()
        self.addCleanup(self.model.stop)

    def test_live_report_schedules_without_batch_inference_and_retry_is_idempotent(self):
        with patch.object(Store,'submit',side_effect=AssertionError('must be background')):
            first=self.service.round_report(self.body)
            second=self.service.round_report(self.body)
        self.assertTrue(first['offline_analysis']['accepted'])
        self.assertEqual(first['event_id'],second['event_id'])
        self.assertEqual(self.mock_model.call_count,1)
        self.assertEqual(self.service.batch_status()['enqueue_counts'],{'pending':1})
        self.service.enqueue_pending_rounds()
        self.service.enqueue_pending_rounds()
        store=Store(self.service.DATA/'batch-jobs.sqlite3')
        jobs=store.inspect()
        self.assertEqual(len(jobs),1)
        self.assertEqual(jobs[0]['provenance']['origin'],'live')
        self.assertEqual(jobs[0]['provenance']['source_id'],self.body.source_id)
        self.assertEqual(jobs[0]['provenance']['session_id'],str(self.body.session_id))
        self.assertEqual(jobs[0]['provenance']['workout_mode'],'program')
        self.assertTrue(all(x['state']=='pending' for x in jobs[0]['items']))

    def test_store_failure_leaves_durable_pending_and_report_succeeds(self):
        result=self.service.round_report(self.body)
        with patch.object(Store,'submit',side_effect=OSError('fixture disk error')):
            self.service.enqueue_pending_rounds()
        status=self.service.batch_status(self.body.request_id)
        self.assertEqual(status['state'],'pending')
        self.assertEqual(status['last_error'],'OSError')
        self.assertEqual(result['constraint'],'Follow source')
        self.service.enqueue_pending_rounds()
        self.assertEqual(self.service.batch_status(self.body.request_id)['state'],'enqueued')

    def test_report_failure_does_not_discard_batch_input(self):
        from fastapi import HTTPException
        self.mock_model.side_effect=RuntimeError('fixture model offline')
        with self.assertRaises(HTTPException):self.service.round_report(self.body)
        with self.service.db() as db:
            self.assertEqual(db.execute('SELECT count(*) FROM requests').fetchone()[0],0)
        self.service.enqueue_pending_rounds()
        self.assertEqual(self.service.batch_status(self.body.request_id)['state'],'enqueued')

    def test_failed_schedule_does_not_interrupt_report(self):
        original=self.service.db
        calls=0
        def failing_schedule_db():
            nonlocal calls
            calls+=1
            if calls==2:raise OSError('fixture receipt failure')
            return original()
        with patch.object(self.service,'db',side_effect=failing_schedule_db):
            result=self.service.round_report(self.body)
        self.assertEqual(result['constraint'],'Follow source')
        self.assertFalse(result['offline_analysis']['accepted'])
        recovered=self.service.round_report(self.body)
        self.assertTrue(recovered['offline_analysis']['accepted'])
        self.assertEqual(self.mock_model.call_count,1)

    def test_synthetic_smoke_keeps_its_origin(self):
        body=self.body.model_copy(update={'origin':'synthetic'})
        receipt=self.service.schedule_round_batch(body)
        self.service.enqueue_pending_rounds()
        store=Store(self.service.DATA/'batch-jobs.sqlite3')
        self.assertEqual(store.inspect(receipt['job_id'])[0]['provenance']['origin'],'synthetic')

    def test_status_endpoint_requires_authorization(self):
        import asyncio
        async def request(headers):
            messages=[]
            async def receive():return {'type':'http.request','body':b'','more_body':False}
            async def send(message):messages.append(message)
            await self.service.app({'type':'http','asgi':{'version':'3.0'},'http_version':'1.1',
                'method':'GET','scheme':'http','path':'/v1/batch/status','raw_path':b'/v1/batch/status',
                'query_string':b'','root_path':'','headers':headers,'server':('test',80),'client':('test',1)},receive,send)
            return next(m['status'] for m in messages if m['type']=='http.response.start')
        self.assertEqual(asyncio.run(request([])),401)
        self.assertEqual(asyncio.run(request([(b'authorization',('Bearer '+self.service.TOKEN).encode())])),200)

if __name__=='__main__':unittest.main()
