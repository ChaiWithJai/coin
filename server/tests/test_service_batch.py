"""Live reports durably schedule offline work without executing a batch model."""
import importlib.util
import json
import os
import sys
import tempfile
import unittest
import uuid
from pathlib import Path
from unittest.mock import patch

SERVER=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(SERVER))
from batch_jobs import Store,VERSION

def bounded_output(result,kind='report',**extra):
    gate=({'evidence_status':'counts_only_not_technique_or_adherence_evaluation','language':'en'} if kind=='report'
          else {'assessment_scope':'observed_events_only'})
    return dict(result=result,prompt_version=VERSION,output_gate=gate,**extra)

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

    def test_runtime_activity_id_survives_round_and_outbox(self):
        activity_id=uuid.uuid4()
        body=self.body.model_copy(update={'activity_instance_id':activity_id,'duration_s':12})
        self.service.round_report(body)
        self.assertEqual(str(self.mock_model.call_args.args[0]['activity_instance_id']),str(activity_id))
        with self.service.OUTBOX.connect() as db:
            payload=json.loads(db.execute('SELECT payload FROM events').fetchone()[0])
        self.assertEqual(payload['activity_instance_id'],str(activity_id))
        self.service.enqueue_pending_rounds()
        store=Store(self.service.DATA/'batch-jobs.sqlite3')
        job=store.inspect()[0]
        self.assertEqual(job['provenance']['activity_instance_id'],str(activity_id))

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

    def queued_analysis(self):
        receipt=self.service.schedule_round_batch(self.body)
        self.service.enqueue_pending_rounds()
        return receipt['job_id'],Store(self.service.DATA/'batch-jobs.sqlite3')

    def test_pending_analysis_is_distinct_from_enqueue_receipt(self):
        self.service.schedule_round_batch(self.body)
        status=self.service.batch_status(self.body.request_id)
        self.assertEqual(status['state'],'pending')
        self.assertEqual(status['analysis']['state'],'awaiting_enqueue')
        self.assertFalse((self.service.DATA/'batch-jobs.sqlite3').exists())
        self.service.enqueue_pending_rounds()
        status=self.service.batch_status(self.body.request_id)
        self.assertEqual(status['state'],'enqueued')
        self.assertEqual(status['analysis']['state'],'pending')
        self.assertEqual(status['analysis']['counts'],{'pending':2})

    def test_completed_analysis_excludes_prompts_and_receipt_input(self):
        job,store=self.queued_analysis()
        secret='DO_NOT_EXPOSE_STORED_PROMPT'
        report={'observation':'One observed exchange.','focus':'Follow the source.','limitations':'Rule candidate only.'}
        with store.db() as db:
            db.execute("UPDATE jobs SET state='complete' WHERE id=?",(job,))
            db.execute("UPDATE items SET state='complete',output=? WHERE job_id=? AND kind='report'",
                (json.dumps(bounded_output(dict(report,unexpected_raw=secret),request=secret,raw_response=secret)),job))
            db.execute("UPDATE items SET state='complete',output=? WHERE job_id=? AND kind='exchange'",
                (json.dumps(bounded_output({'decision':'quiet','raw_choice':secret},kind='exchange',request=secret)),job))
        status=self.service.batch_status(self.body.request_id,self.body.session_id)
        self.assertEqual(status['state'],'enqueued')
        self.assertEqual(status['analysis']['state'],'complete')
        self.assertEqual(status['analysis']['report'],report)
        self.assertEqual(status['analysis']['counts'],{'complete':2})
        encoded=json.dumps(status)
        for value in (secret,self.body.source_title,self.body.source_instructions,'peakSpeed'):
            self.assertNotIn(value,encoded)

    def test_failed_item_exposes_error_type_and_hides_stale_result_on_retry(self):
        job,store=self.queued_analysis()
        with store.db() as db:
            db.execute("UPDATE jobs SET state='partial' WHERE id=?",(job,))
            db.execute("UPDATE items SET state='failed',output=?,error=? WHERE job_id=? AND kind='report'",
                (json.dumps({'result':{'observation':'stale'},'request':'private input'}),
                 json.dumps({'type':'ModelResponseError','message':'private input'}),job))
        status=self.service.batch_status(self.body.request_id)
        self.assertEqual(status['analysis']['state'],'partial')
        self.assertIsNone(status['analysis']['report'])
        self.assertEqual(next(i for i in status['analysis']['items'] if i['kind']=='report')['error_type'],'ModelResponseError')
        self.assertNotIn('private input',json.dumps(status))
        store.control(job,'retry')
        status=self.service.batch_status(self.body.request_id)
        self.assertEqual(status['analysis']['state'],'pending')
        self.assertIsNone(status['analysis']['report'])
        self.assertNotIn('stale',json.dumps(status))

    def test_legacy_report_and_exchange_results_are_withheld_without_rewriting(self):
        job,store=self.queued_analysis()
        output=json.dumps({'prompt_version':'completed-round-batch-v1','result':{'observation':'legacy unrestricted advice','decision':'cue'}})
        with store.db() as db:
            db.execute("UPDATE jobs SET state='complete' WHERE id=?",(job,))
            db.execute("UPDATE items SET state='complete',output=? WHERE job_id=?",(output,job))
        status=self.service.batch_status(self.body.request_id)
        self.assertEqual(status['analysis']['state'],'legacy_unreviewed')
        self.assertIsNone(status['analysis']['report'])
        self.assertTrue(all('result' not in item for item in status['analysis']['items']))
        self.assertNotIn('legacy unrestricted advice',json.dumps(status))
        with store.db() as db:
            self.assertTrue(all(row[0]==output for row in db.execute('SELECT output FROM items WHERE job_id=?',(job,))))

    def test_current_version_still_requires_bounded_report_gate_and_correct_language(self):
        job,store=self.queued_analysis()
        for gate in ({},{'evidence_status':'unreviewed','language':'en'},
                     {'evidence_status':'counts_only_not_technique_or_adherence_evaluation','language':'fr'}):
            with store.db() as db:
                db.execute("UPDATE jobs SET state='complete' WHERE id=?",(job,))
                db.execute("UPDATE items SET state='complete',output=? WHERE job_id=? AND kind='report'",
                    (json.dumps({'prompt_version':VERSION,'result':{'observation':'withheld'},'output_gate':gate}),job))
            status=self.service.batch_status(self.body.request_id)
            self.assertEqual(status['analysis']['state'],'legacy_unreviewed')
            self.assertIsNone(status['analysis']['report'])
            self.assertNotIn('"observation": "withheld"',json.dumps(status))

    def test_identity_mismatch_never_returns_other_origin_or_session(self):
        job,store=self.queued_analysis()
        original=store.inspect(job)[0]['provenance']
        for key,value in [('origin','synthetic'),('session_id',str(uuid.uuid4())),('request_id',str(uuid.uuid4()))]:
            with store.db() as db:db.execute('UPDATE jobs SET provenance=? WHERE id=?',(json.dumps(dict(original,**{key:value})),job))
            status=self.service.batch_status(self.body.request_id)
            self.assertEqual(status['analysis']['state'],'identity_mismatch')
            self.assertEqual(status['analysis']['items'],[])
        from fastapi import HTTPException
        with self.assertRaises(HTTPException) as caught:self.service.batch_status(self.body.request_id,uuid.uuid4())
        self.assertEqual(caught.exception.status_code,404)

    def test_uppercase_ios_session_uuid_matches_and_keeps_source_spelling(self):
        job,store=self.queued_analysis()
        uppercase=str(self.body.session_id).upper()
        with self.service.db() as db:
            row=db.execute('SELECT payload FROM batch_enqueues WHERE request_id=?',(str(self.body.request_id),)).fetchone()
            record=json.loads(row[0]);record['session_id']=uppercase
            db.execute('UPDATE batch_enqueues SET payload=? WHERE request_id=?',(json.dumps(record),str(self.body.request_id)))
        # Queue metadata and the receipt may legitimately differ in letter case.
        provenance=store.inspect(job)[0]['provenance']
        provenance['request_id']=provenance['request_id'].upper()
        report={'observation':'One exchange.','focus':'Follow source.','limitations':'Candidate evidence.'}
        with store.db() as db:
            db.execute('UPDATE jobs SET provenance=?,state=? WHERE id=?',(json.dumps(provenance),'complete',job))
            db.execute("UPDATE items SET state='complete',output=? WHERE job_id=? AND kind='report'",(json.dumps(bounded_output(report)),job))
        status=self.service.batch_status(self.body.request_id,uuid.UUID(uppercase))
        self.assertEqual(status['session_id'],uppercase)
        self.assertEqual(status['analysis']['state'],'complete')
        self.assertEqual(status['analysis']['report'],report)
        from fastapi import HTTPException
        with self.assertRaises(HTTPException) as caught:self.service.batch_status(self.body.request_id,uuid.uuid4())
        self.assertEqual(caught.exception.status_code,404)

    def test_missing_request_and_missing_job_are_explicit(self):
        from fastapi import HTTPException
        with self.assertRaises(HTTPException) as caught:self.service.batch_status(uuid.uuid4())
        self.assertEqual(caught.exception.status_code,404)
        job,store=self.queued_analysis()
        with store.db() as db:db.execute('DELETE FROM jobs WHERE id=?',(job,))
        self.assertEqual(self.service.batch_status(self.body.request_id)['analysis']['state'],'missing')

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
