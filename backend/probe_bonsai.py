"""Bounded integration request to the existing GB10 service; not a throughput test."""
import sys, json, subprocess, time, hashlib
from pathlib import Path
import mlflow
ROOT=Path(__file__).resolve().parent
sys.path.insert(0,'/Users/jaibhagat/code/prismml/outputs/ale-browser-latency/queue')
import gpu_queue
mlflow.set_tracking_uri('http://127.0.0.1:5210')
mlflow.set_experiment('boxing-app-inference')
manifest=json.loads((ROOT/'model-manifest.json').read_text())
request={'model':'bonsai2-27b','temperature':0,'max_tokens':256,
         'chat_template_kwargs':{'enable_thinking':False},
         'messages':[{'role':'system','content':'You help an adult boxer review user-confirmed notes. You have not seen any video. Do not invent measurements, diagnose injuries, or prescribe hard sparring. Reply only with a JSON object with keys observation, drill, limitation. Use French. Keep each value under 30 words.'},
                     {'role':'user','content':'Confirmed observation from my own review at 00:12: my rear hand stays low after my jab during solo shadowboxing. Give one gentle technical drill with no equipment.'}]}
@mlflow.trace(name='bonsai_round_review_probe',span_type='LLM')
def call_model(payload):
    script='''import json,sys,urllib.request,time\np=json.load(sys.stdin)\nt=time.perf_counter()\nr=urllib.request.Request("http://127.0.0.1:5214/v1/chat/completions",data=json.dumps(p).encode(),headers={"Content-Type":"application/json"})\nwith urllib.request.urlopen(r,timeout=90) as response: out=json.load(response)\nprint(json.dumps({"response":out,"http_elapsed_seconds":time.perf_counter()-t}))'''
    import shlex
    p=subprocess.run(['ssh','-o','BatchMode=yes','-o','ConnectTimeout=8','gb10','python3 -c '+shlex.quote(script)],input=json.dumps(payload),text=True,capture_output=True,timeout=105)
    if p.returncode:raise RuntimeError(p.stderr[-2000:])
    return json.loads(p.stdout)
job_id='coin-bonsai-integration-'+str(time.time_ns())
gpu_queue.put(job_id,'gb10',{'kind':'existing-service-integration','model_sha256':manifest['model_sha256'],'max_tokens':256,'note':'User-requested app integration on resident service. No new server, training or isolated performance claim.'})
claim=gpu_queue.claim('gb10',job_id)
if claim is None:raise RuntimeError('Shared GPU queue is occupied; request was not sent')
try:
    with mlflow.start_run(run_name='bonsai-first-round-review',tags={'evidence_type':'synthetic_text_integration','visual_input':'none','hardware':'GB10','queue_job_id':job_id}) as run:
        mlflow.log_dict(manifest,'model-manifest.json');mlflow.log_dict(request,'request.json')
        result=call_model(request)
        mlflow.log_dict(result,'response.json')
        content=result['response']['choices'][0]['message'].get('content','')
        try:
            obj=json.loads(content);valid=set(obj)=={'observation','drill','limitation'} and all(isinstance(v,str) for v in obj.values())
        except (ValueError,TypeError):valid=False
        mlflow.log_metrics({'schema_valid':float(valid),'shared_service_http_seconds':result['http_elapsed_seconds']})
        mlflow.flush_trace_async_logging()
        trace_id=mlflow.get_last_active_trace_id();assert mlflow.get_trace(trace_id)
        result.update(run_id=run.info.run_id,trace_id=trace_id,schema_valid=valid)
        (ROOT/'bonsai-integration-result.json').write_text(json.dumps(result,indent=2,ensure_ascii=False))
        print(json.dumps({'run_id':run.info.run_id,'trace_id':trace_id,'schema_valid':valid,'content':content,'http_seconds':result['http_elapsed_seconds']},ensure_ascii=False))
    gpu_queue.update(job_id,'completed','Resident service returned; raw result retained in boxing-app-inference. Not an isolated benchmark.')
except Exception:
    gpu_queue.update(job_id,'needs_review','Integration failed or timed out; inspect resident service before any retry.')
    raise
