"""Durable local event outbox. A single delivery worker owns an expiring lease.

At-least-once delivery: a remote success followed by a crash can replay an event.
Sinks must use event_id for deduplication. Never put raw video or credentials here.
"""
import json
import sqlite3
import time
import uuid
from pathlib import Path

class Outbox:
    MAX_CLAIM = 1000
    def __init__(self,path):
        self.path=Path(path)
        self.path.parent.mkdir(parents=True,exist_ok=True)
        with self.connect() as db:
            db.execute('PRAGMA journal_mode=WAL')
            db.execute('''CREATE TABLE IF NOT EXISTS events (
                id TEXT PRIMARY KEY, payload TEXT NOT NULL, state TEXT NOT NULL DEFAULT 'pending',
                attempts INTEGER NOT NULL DEFAULT 0, available REAL NOT NULL DEFAULT 0,
                lease_until REAL NOT NULL DEFAULT 0, lease_owner TEXT, last_error TEXT,
                delivered_at REAL)''')
    def connect(self):
        db=sqlite3.connect(self.path,timeout=2)
        db.row_factory=sqlite3.Row
        db.execute('PRAGMA synchronous=FULL')
        return db
    def enqueue(self,payload,event_id=None):
        event_id=str(uuid.UUID(event_id)) if event_id else str(uuid.uuid4())
        encoded=json.dumps(payload,sort_keys=True,allow_nan=False)
        if len(encoded.encode())>256_000:raise ValueError('Event too large; store media separately')
        with self.connect() as db:
            prior=db.execute('SELECT payload FROM events WHERE id=?',(event_id,)).fetchone()
            if prior and prior['payload']!=encoded:raise ValueError('Event ID reused with different payload')
            db.execute('INSERT OR IGNORE INTO events(id,payload) VALUES (?,?)',(event_id,encoded))
        return event_id
    def claim(self,now=None,lease_seconds=120):
        events=self.claim_many(1,now=now,lease_seconds=lease_seconds)
        return events[0] if events else None
    def claim_many(self,limit,now=None,lease_seconds=120):
        """Atomically lease up to ``limit`` available events.

        One owner token covers the batch, while every returned event retains its
        own ID and attempt count.  A lost response is safe: the leases expire and
        the events become claimable again.
        """
        if isinstance(limit,bool) or not isinstance(limit,int) or not 1<=limit<=self.MAX_CLAIM:
            raise ValueError(f'Claim limit must be between 1 and {self.MAX_CLAIM}')
        if isinstance(lease_seconds,bool) or not isinstance(lease_seconds,(int,float)) or lease_seconds<=0:
            raise ValueError('Lease duration must be positive')
        now=time.time() if now is None else now
        owner=str(uuid.uuid4())
        with self.connect() as db:
            db.execute('BEGIN IMMEDIATE')
            rows=db.execute("SELECT * FROM events WHERE (state='pending' AND available<=?) OR (state='leased' AND lease_until<=?) ORDER BY rowid LIMIT ?",(now,now,limit)).fetchall()
            if not rows:return []
            db.executemany("UPDATE events SET state='leased',lease_until=?,lease_owner=?,attempts=attempts+1 WHERE id=?",((now+lease_seconds,owner,row['id']) for row in rows))
            return [{'event_id':row['id'],'payload':json.loads(row['payload']),'owner':owner,'attempts':row['attempts']+1} for row in rows]
    def finish(self,event,success,error=None,now=None):
        now=time.time() if now is None else now
        with self.connect() as db:
            changed=self._finish(db,event,success,error,now)
            if changed!=1:raise RuntimeError('Lease no longer owned')
    def _finish(self,db,event,success,error,now):
        if success:
            return db.execute("UPDATE events SET state='delivered',delivered_at=?,lease_until=0 WHERE id=? AND state='leased' AND lease_owner=?",(now,event['event_id'],event['owner'])).rowcount
        delay=min(300,2**min(event['attempts'],8))
        return db.execute("UPDATE events SET state='pending',available=?,lease_until=0,last_error=? WHERE id=? AND state='leased' AND lease_owner=?",(now+delay,(error or 'delivery failed')[:500],event['event_id'],event['owner'])).rowcount
    def finish_many(self,results,now=None):
        """Finish independently delivered events in one transaction.

        A stale lease is reported for that event without rolling back valid
        sibling results.  Delivery failures keep their individual retry delay
        and error text.
        """
        if not isinstance(results,list) or len(results)>self.MAX_CLAIM:
            raise ValueError(f'Results must be a list of at most {self.MAX_CLAIM} items')
        now=time.time() if now is None else now
        outcomes=[]
        with self.connect() as db:
            db.execute('BEGIN IMMEDIATE')
            for result in results:
                event=result['event']
                success=result['success']
                changed=self._finish(db,event,success,result.get('error'),now)
                outcome={'event_id':event['event_id'],'finished':changed==1,'success':bool(success)}
                if changed!=1:outcome['error']='Lease no longer owned'
                elif not success:outcome['error']=(result.get('error') or 'delivery failed')[:500]
                outcomes.append(outcome)
        return outcomes
    def deliver_one(self,sink,now=None):
        event=self.claim(now)
        if event is None:return False
        try:sink(event['event_id'],event['payload'])
        except Exception as exc:
            self.finish(event,False,type(exc).__name__,now)
            return False
        self.finish(event,True,now=now)
        return True
    def counts(self):
        with self.connect() as db:return dict(db.execute('SELECT state,count(*) FROM events GROUP BY state').fetchall())
