import json
from pathlib import Path
import mlflow
from pipeline import CueEngine, Window, Observation
mlflow.set_tracking_uri('http://127.0.0.1:5210')
exp=mlflow.set_experiment('boxing-app-inference')
with mlflow.start_run(run_name='rules-contract-fixture',tags={'evidence_type':'synthetic_contract_test','models_called':'none'}) as run:
    result=CueEngine().process(Window('synthetic-fixture',1,10000,'fr',(Observation('rear_hand_low',1,'user_confirmed',10000),)),10100)
    trace_id=mlflow.get_last_active_trace_id()
    mlflow.flush_trace_async_logging()
    trace=mlflow.get_trace(trace_id)
    assert trace is not None
    names=[span.name for span in trace.data.spans]
    assert 'live_window' in names and 'evidence_gate' in names
    mlflow.log_dict({'result':result,'trace_id':trace_id,'spans':names},'verification.json')
    mlflow.log_artifact(__file__)
    report={'run_id':run.info.run_id,'trace_id':trace_id,'spans':names,'evidence_type':'synthetic fixture; no visual accuracy or model inference established'}
    Path(__file__).with_name('trace-verification.json').write_text(json.dumps(report,indent=2))
    print(json.dumps(report))
