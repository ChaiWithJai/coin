"""Mac-side bounded export for a Mac file-artifact MLflow server."""
import subprocess,json,os
REMOTE='/home/chaiwithjai/Documents/code/coin-boxing/'
MAX_BATCH=1000
SECONDS_PER_EVENT=5
MAX_LEASE_SECONDS=7200
def remote(action,payload=None):
 ssh=['ssh','-o','BatchMode=yes','-o','ConnectTimeout=8']
 if host:=os.environ.get('COIN_SSH_HOSTNAME'):ssh+=['-o','HostName='+host]
 p=subprocess.run(ssh+['gb10',REMOTE+'.venv/bin/python '+REMOTE+'outbox_bridge.py '+action],input=json.dumps(payload) if payload else None,text=True,capture_output=True,timeout=30)
 if p.returncode:raise RuntimeError(p.stderr[-1000:])
 return json.loads(p.stdout)
def drain(limit=20):
 if isinstance(limit,bool) or not isinstance(limit,int) or not 1<=limit<=MAX_BATCH:raise ValueError(f'Limit must be between 1 and {MAX_BATCH}')
 lease_seconds=min(MAX_LEASE_SECONDS,max(120,limit*SECONDS_PER_EVENT))
 events=remote('claim-many',{'limit':limit,'lease_seconds':lease_seconds})
 sink=None;delivered=0;results=[];failures=[]
 for event in events:
  try:
   if sink is None:
    from mlflow_sink import MLflowSink
    sink=MLflowSink()
   sink(event['event_id'],event['payload'])
  except Exception as exc:
   error=type(exc).__name__
   results.append({'event':event,'success':False,'error':error})
   failures.append((event['event_id'],error))
  else:
   results.append({'event':event,'success':True});delivered+=1
 if results:
  outcomes=remote('finish-many',{'results':results})
  expected=[result['event']['event_id'] for result in results]
  returned=[outcome.get('event_id') for outcome in outcomes]
  if returned!=expected:raise RuntimeError('Remote finish response did not cover the claimed batch')
  stale=[outcome['event_id'] for outcome in outcomes if not outcome.get('finished')]
  if stale:raise RuntimeError('Remote leases no longer owned: '+','.join(stale))
 states=remote('counts')
 if delivered or any(state!='delivered' for state in states):
  print(json.dumps({'claimed_this_pass':len(events),'delivered_this_pass':delivered,'failed_this_pass':len(failures),'remote_states':states}))
 if failures:raise RuntimeError(f'{len(failures)} telemetry event(s) failed delivery')
if __name__=='__main__':drain()
