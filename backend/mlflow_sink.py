"""Deliver queued session events to MLflow without blocking coaching."""
import mlflow
from mlflow import MlflowClient
from telemetry import Outbox
import uuid

class MLflowSink:
    def __init__(self,uri='http://127.0.0.1:5210',experiment='boxing-app-inference'):
        mlflow.set_tracking_uri(uri)
        self.client=MlflowClient(uri)
        self.experiment=mlflow.set_experiment(experiment)
    def __call__(self,event_id,payload):
        event_id=str(uuid.UUID(event_id))
        existing=self.client.search_runs([self.experiment.experiment_id],filter_string=f"tags.event_id = '{event_id}' and attributes.status = 'FINISHED'",max_results=1)
        if existing:return
        decision=payload.get('decision',{})
        names=[st.get('name','') for st in payload.get('stages',[])]
        kind='round_report' if any(n.endswith('round_report') for n in names) else 'coaching_event'
        facts=decision.get('facts',{}) if isinstance(decision,dict) else {}
        run_name=f"round {facts.get('round','?')} · {facts.get('exchanges','?')} exchanges · {facts.get('main_issue','')}" if kind=='round_report' else 'queued-coaching-event'
        with mlflow.start_run(run_name=run_name,experiment_id=self.experiment.experiment_id,tags={
            'event_id':event_id,
            'record_kind':'durable_event',
            'run_scope':'telemetry_export',
            'delivery_semantics':'at_least_once',
            'product_event_status':str(decision.get('status',decision.get('action','recorded'))),
            'event_kind':kind,
            'main_issue':str(facts.get('main_issue','')),
        }) as run:
            for k in ('exchanges','punches','probe_openers','commit_openers','reset_rate','small_model_opener_agreement'):
                if isinstance(facts.get(k),(int,float)):mlflow.log_metric(k,facts[k])
            with mlflow.start_span(name=kind,span_type='CHAIN') as span:
                mlflow.update_current_trace(metadata={'mlflow.trace.session':payload['session_id'],'event_id':event_id})
                span.set_inputs({'window_id':payload.get('window_id'),'captured_at':payload.get('captured_at'),'model_versions':payload.get('model_versions',{})})
                span.set_outputs(decision)
                for stage in payload.get('stages',[]):
                    with mlflow.start_span(name=stage['name'],span_type=stage.get('span_type','TOOL')) as child:
                        child.set_inputs(stage.get('inputs',{}));child.set_outputs(stage.get('outputs',{}))
                        child.set_attribute('observed_duration_ms',stage.get('duration_ms'))
                span.set_attribute('timing_semantics','Replay time is export time; original stage durations are explicit attributes.')
            mlflow.flush_trace_async_logging()
            trace_id=mlflow.get_last_active_trace_id()
            if not mlflow.get_trace(trace_id):raise RuntimeError('Trace readback failed')
            mlflow.log_dict(payload,'event.json')
            mlflow.set_tag('trace_id',trace_id)
