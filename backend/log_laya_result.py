import json
from pathlib import Path
import mlflow
ROOT=Path(__file__).resolve().parent
report=json.loads((ROOT/'laya-cpu-result.json').read_text())
expected={'confirmed-fr':'cue','occluded-en':'quiet','cooldown-fr':'quiet'}
mlflow.set_tracking_uri('http://127.0.0.1:5210');mlflow.set_experiment('boxing-app-inference')
with mlflow.start_run(run_name='laya-cpu-three-case-baseline',tags={'evidence_type':'synthetic_development_cases','human_labels':'none','trace_timing':'posthoc_import_of_actual_remote_results','hardware':'GB10 CPU'}) as run:
 mlflow.log_artifact(str(ROOT/'laya-cpu-result.json'));mlflow.log_artifact(str(ROOT/'laya-manifest.json'));mlflow.log_artifact(str(ROOT/'gb10-python-lock.txt'))
 correct=0;trace_ids=[]
 for entry in report['results']:
  case_id=entry['case']['id'];choice=entry['result']['answers']['intervention']['choice'];correct+=choice==expected[case_id]
  with mlflow.start_span(name='laya_intervention_observed',span_type='LLM') as span:
   span.set_inputs({'state':entry['case']['state'],'questions':entry['questions']});span.set_outputs(entry['result'])
   span.set_attribute('observed_inference_seconds',entry['seconds']);span.set_attribute('timing_semantics','Posthoc trace import; span duration is not inference latency')
   span.set_attribute('model_revision',report['manifest']['revision']);span.set_attribute('expected_decision',expected[case_id]);span.set_attribute('case_id',case_id)
  mlflow.flush_trace_async_logging();tid=mlflow.get_last_active_trace_id();assert mlflow.get_trace(tid);trace_ids.append(tid)
 mlflow.log_metrics({'development_accuracy':correct/len(expected),'development_case_count':len(expected),'model_load_seconds':report['load_seconds']})
 assessment={'run_id':run.info.run_id,'trace_ids':trace_ids,'correct':correct,'cases':3,'label_source':'predefined synthetic contract expectations, not human film labels','decision':'Do not promote zero-shot Laya to live cue authority. Hard visibility/cooldown gates remain mandatory.'}
 mlflow.log_dict(assessment,'assessment.json');(ROOT/'laya-assessment.json').write_text(json.dumps(assessment,indent=2));print(json.dumps(assessment))
