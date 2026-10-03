"""SSH-only outbox transport. No public network listener."""
import sys,json
from pathlib import Path
from telemetry import Outbox
box=Outbox(Path(__file__).resolve().parent/'state/events.sqlite3')
if sys.argv[1]=='claim':print(json.dumps(box.claim()))
elif sys.argv[1]=='claim-many':
 p=json.load(sys.stdin);print(json.dumps(box.claim_many(p.get('limit',20),lease_seconds=p.get('lease_seconds',120))))
elif sys.argv[1]=='finish':
 p=json.load(sys.stdin);box.finish(p['event'],p['success'],p.get('error'));print('{}')
elif sys.argv[1]=='finish-many':
 p=json.load(sys.stdin);print(json.dumps(box.finish_many(p['results'])))
elif sys.argv[1]=='counts':print(json.dumps(box.counts()))
else:raise ValueError('Unknown operation')
