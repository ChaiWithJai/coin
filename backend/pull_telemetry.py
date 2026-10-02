"""Mac-side bounded export for a Mac file-artifact MLflow server."""
import subprocess,json,os
REMOTE='/home/chaiwithjai/Documents/code/coin-boxing/'
def remote(action,payload=None):
 ssh=['ssh','-o','BatchMode=yes','-o','ConnectTimeout=8']
 if host:=os.environ.get('COIN_SSH_HOSTNAME'):ssh+=['-o','HostName='+host]
 p=subprocess.run(ssh+['gb10',REMOTE+'.venv/bin/python '+REMOTE+'outbox_bridge.py '+action],input=json.dumps(payload) if payload else None,text=True,capture_output=True,timeout=30)
 if p.returncode:raise RuntimeError(p.stderr[-1000:])
 return json.loads(p.stdout)
def drain(limit=20):
 sink=None;delivered=0
 for _ in range(limit):
  event=remote('claim')
  if event is None:break
  try:
   if sink is None:
    from mlflow_sink import MLflowSink
    sink=MLflowSink()
   sink(event['event_id'],event['payload'])
  except Exception as exc:
   remote('finish',{'event':event,'success':False,'error':type(exc).__name__});raise
  remote('finish',{'event':event,'success':True});delivered+=1
 states=remote('counts')
 if delivered or any(state!='delivered' for state in states):
  print(json.dumps({'delivered_this_pass':delivered,'remote_states':states}))
if __name__=='__main__':drain()
