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
        now=time.time() if now is None else now
        owner=str(uuid.uuid4())
        with self.connect() as db:
            db.execute('BEGIN IMMEDIATE')
            row=db.execute("SELECT * FROM events WHERE (state='pending' AND available<=?) OR (state='leased' AND lease_until<=?) ORDER BY rowid LIMIT 1",(now,now)).fetchone()
            if row is None:return None
            db.execute("UPDATE events SET state='leased',lease_until=?,lease_owner=?,attempts=attempts+1 WHERE id=?",(now+lease_seconds,owner,row['id']))
            return {'event_id':row['id'],'payload':json.loads(row['payload']),'owner':owner,'attempts':row['attempts']+1}
    def finish(self,event,success,error=None,now=None):
        now=time.time() if now is None else now
        with self.connect() as db:
            if success:
                changed=db.execute("UPDATE events SET state='delivered',delivered_at=?,lease_until=0 WHERE id=? AND state='leased' AND lease_owner=?",(now,event['event_id'],event['owner'])).rowcount
            else:
                delay=min(300,2**min(event['attempts'],8))
                changed=db.execute("UPDATE events SET state='pending',available=?,lease_until=0,last_error=? WHERE id=? AND state='leased' AND lease_owner=?",(now+delay,(error or 'delivery failed')[:500],event['event_id'],event['owner'])).rowcount
            if changed!=1:raise RuntimeError('Lease no longer owned')
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
