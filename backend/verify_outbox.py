from pathlib import Path
import json
from telemetry import Outbox
from mlflow_sink import MLflowSink
root=Path(__file__).resolve().parents[3]
box=Outbox(root/'work/telemetry/events.sqlite3')
eid=box.enqueue({'session_id':'synthetic-durable-fixture','window_id':'w1','decision':{'action':'silence','reason':'insufficient_evidence'},'stages':[{'name':'evidence_gate','inputs':{'visible':False},'outputs':{'allow_cue':False},'duration_ms':0.1}]})
# Create a new instance to establish local persistence before export.
box=Outbox(box.path);assert box.deliver_one(MLflowSink())
assert box.counts()['delivered']>=1
print(json.dumps({'event_id':eid,'states':box.counts(),'scope':'Synthetic event persisted, exported, and trace read back. Not a live camera trace.'}))
