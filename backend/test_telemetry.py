import pytest
from telemetry import Outbox

def test_restart_failure_retry_and_dedupe(tmp_path):
    path=tmp_path/'events.db'
    box=Outbox(path);eid=box.enqueue({'session':'synthetic','action':'silence'})
    assert box.enqueue({'session':'synthetic','action':'silence'},eid)==eid
    with pytest.raises(ValueError):box.enqueue({'different':True},eid)
    restarted=Outbox(path)
    def unavailable(*args):raise OSError('network down')
    assert not restarted.deliver_one(unavailable,now=10)
    delivered=[]
    assert not restarted.deliver_one(lambda *args:delivered.append(args),now=11)
    assert restarted.deliver_one(lambda *args:delivered.append(args),now=12)
    assert len(delivered)==1 and delivered[0][0]==eid
    assert restarted.counts()=={'delivered':1}

def test_worker_crash_lease_expiry_and_stale_ack(tmp_path):
    box=Outbox(tmp_path/'events.db');box.enqueue({'kind':'fixture'})
    first=box.claim(now=10,lease_seconds=5)
    assert box.claim(now=14) is None
    second=Outbox(box.path).claim(now=15)
    assert second['event_id']==first['event_id'] and second['owner']!=first['owner']
    with pytest.raises(RuntimeError):box.finish(first,True,now=16)
    box.finish(second,True,now=16)

def test_invalid_and_oversized_payloads(tmp_path):
    box=Outbox(tmp_path/'events.db')
    with pytest.raises(ValueError):box.enqueue({'secret_blob':'x'*256001})
    with pytest.raises(ValueError):box.enqueue({'value':float('nan')})
