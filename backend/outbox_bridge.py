"""SSH-only outbox transport. No public network listener."""
import sys,json
from pathlib import Path
from telemetry import Outbox
box=Outbox(Path(__file__).resolve().parent/'state/events.sqlite3')
if sys.argv[1]=='claim':print(json.dumps(box.claim()))
elif sys.argv[1]=='finish':
 p=json.load(sys.stdin);box.finish(p['event'],p['success'],p.get('error'));print('{}')
elif sys.argv[1]=='counts':print(json.dumps(box.counts()))
else:raise ValueError('Unknown operation')
