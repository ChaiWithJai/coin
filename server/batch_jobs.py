"""Offline completed-round analysis and immutable source-curriculum annotations.

Only `work` makes model requests. Run outside live sessions. One worker owns the
queue; claims expire after crashes. A crash after inference but before commit can
repeat a call (at-least-once inference). Completed results are cached. Exported
telemetry uses stable event IDs and the existing durable outbox.
"""
import argparse
import hashlib
import json
import math
import re
import sqlite3
import time
import urllib.request
import uuid
from pathlib import Path
from contextlib import contextmanager

VERSION = 'completed-round-batch-v1'
CURRICULUM_VERSION = 'source-annotation-atomic-v2.1'
MAX_EXCHANGES = 200
MAX_INPUT_BYTES = 2_000_000

ACTIVITIES = ['shadowboxing', 'bag_work', 'partner_work', 'footwork', 'strength',
              'conditioning', 'mobility', 'recovery', 'unknown']
PHASES = ['initiate', 'interact', 'terminate', 'reset', 'unspecified']
CUES = {
    'follow_source': {'fr': 'Suis la consigne de cet exercice.', 'en': 'Follow this exercise’s instructions.'},
    'steady': {'fr': 'Garde un rythme régulier.', 'en': 'Keep a steady pace.'},
    'recover': {'fr': 'Prends ce temps pour récupérer.', 'en': 'Use this time to recover.'},
}


def encoded(value):
    return json.dumps(value, sort_keys=True, separators=(',', ':'), allow_nan=False)


def digest(value):
    return hashlib.sha256(encoded(value).encode()).hexdigest()


def validate_round(record):
    if not isinstance(record, dict) or record.get('language') not in ('fr', 'en'):
        raise ValueError('Round must have language fr or en')
    exchanges = record.get('exchanges')
    if not isinstance(exchanges, list) or not 0 <= len(exchanges) <= MAX_EXCHANGES:
        raise ValueError('Expected 0..200 completed exchanges')
    ids = set()
    for ex in exchanges:
        if not isinstance(ex, dict) or not isinstance(ex.get('id'), int) or ex['id'] in ids:
            raise ValueError('Exchange IDs must be unique integers')
        ids.add(ex['id'])
        punches = ex.get('punches')
        if not isinstance(punches, list) or not 1 <= len(punches) <= 20:
            raise ValueError('Each exchange must contain 1..20 punches')
        for punch in punches:
            if punch.get('hand') not in ('lead', 'rear') or not isinstance(punch.get('atMs'), (int, float)):
                raise ValueError('Invalid punch event')
    if len(encoded(record).encode()) > MAX_INPUT_BYTES:
        raise ValueError('Round input exceeds bounded size')


class Store:
    def __init__(self, path):
        self.path = Path(path)
        self.path.parent.mkdir(parents=True, exist_ok=True)
        with self.db() as db:
            db.executescript('''
              PRAGMA journal_mode=WAL;
              CREATE TABLE IF NOT EXISTS jobs(id TEXT PRIMARY KEY, input TEXT NOT NULL,
                provenance TEXT NOT NULL, state TEXT NOT NULL, created REAL NOT NULL);
              CREATE TABLE IF NOT EXISTS items(job_id TEXT, item_id TEXT, kind TEXT,
                input TEXT NOT NULL, state TEXT NOT NULL DEFAULT 'pending', attempts INTEGER DEFAULT 0,
                output TEXT, error TEXT, model TEXT, PRIMARY KEY(job_id,item_id));
              CREATE TABLE IF NOT EXISTS cache(key TEXT PRIMARY KEY, output TEXT NOT NULL);
              CREATE TABLE IF NOT EXISTS attempts(job_id TEXT, item_id TEXT, attempt INTEGER,
                state TEXT, output TEXT, error TEXT, model TEXT, PRIMARY KEY(job_id,item_id,attempt));
              CREATE TABLE IF NOT EXISTS worker(id INTEGER PRIMARY KEY CHECK(id=1), owner TEXT, until REAL);
            ''')

    @contextmanager
    def db(self):
        db = sqlite3.connect(self.path, timeout=5)
        db.row_factory = sqlite3.Row
        db.execute('PRAGMA synchronous=FULL')
        try:
            with db:
                yield db
        finally:
            db.close()

    def submit(self, record, provenance, job_id=None):
        validate_round(record)
        if not isinstance(provenance, dict) or provenance.get('origin') not in ('live', 'replay', 'synthetic'):
            raise ValueError('Provenance requires origin live, replay, or synthetic')
        if not provenance.get('source_id'):
            raise ValueError('Provenance requires source_id')
        body, source = encoded(record), encoded(provenance)
        job_id = job_id or digest({'input': record, 'provenance': provenance, 'version': VERSION})
        with self.db() as db:
            row = db.execute('SELECT input,provenance FROM jobs WHERE id=?', (job_id,)).fetchone()
            if row:
                if (row['input'], row['provenance']) != (body, source):
                    raise ValueError('Job ID reused with different input')
                return job_id
            db.execute('INSERT INTO jobs VALUES(?,?,?,?,?)', (job_id, body, source, 'pending', time.time()))
            for ex in record['exchanges']:
                db.execute('INSERT INTO items(job_id,item_id,kind,input) VALUES(?,?,?,?)',
                           (job_id, f'exchange:{ex["id"]}', 'exchange', encoded({'exchange': ex,
                            'drill_id': record.get('drill_id'), 'workout_mode': record.get('workout_mode', 'unknown'),
                            'source': provenance})))
            db.execute('INSERT INTO items(job_id,item_id,kind,input) VALUES(?,?,?,?)',
                       (job_id, 'report', 'report', body))
        return job_id

    def submit_catalog(self, catalog):
        blocks = [(workout, block) for workout in catalog['workouts'] for block in workout['blocks']]
        if not 1 <= len(blocks) <= 2000:
            raise ValueError('Catalog must contain 1..2000 blocks')
        for _, block in blocks:
            if not block.get('id') or not isinstance(block.get('sourceText'), str) or not block['sourceText'].strip():
                raise ValueError('Catalog block needs id and sourceText')
            if len(block['sourceText']) > 12000:
                raise ValueError('Source section too long for bounded annotation')
        job_id = digest({'catalog': catalog, 'version': CURRICULUM_VERSION})
        provenance = {'origin': 'source_curriculum', 'source_id': catalog.get('sourceURL'),
                      'catalog_version': catalog.get('catalogVersion'), 'catalog_sha256': digest(catalog),
                      'annotation_version': CURRICULUM_VERSION}
        with self.db() as db:
            if db.execute('SELECT 1 FROM jobs WHERE id=?', (job_id,)).fetchone():
                return job_id
            db.execute('INSERT INTO jobs VALUES(?,?,?,?,?)',
                       (job_id, encoded(catalog), encoded(provenance), 'pending', time.time()))
            for workout, block in blocks:
                # Immutable source and prescriptions stay beside the proposed annotation.
                data = {'block': block, 'source_sha256': workout.get('sourceSHA256'),
                        'source_text_sha256': digest(block['sourceText']), 'workout_id': workout['id']}
                db.execute('INSERT INTO items(job_id,item_id,kind,input) VALUES(?,?,?,?)',
                           (job_id, 'workout:' + block['id'], 'workout', encoded(data)))
        return job_id

    def control(self, job_id, action):
        with self.db() as db:
            row = db.execute('SELECT state FROM jobs WHERE id=?', (job_id,)).fetchone()
            if not row:
                raise ValueError('Unknown job')
            if action == 'pause':
                if row['state'] != 'complete':
                    db.execute("UPDATE jobs SET state='paused' WHERE id=?", (job_id,))
            elif action in ('resume', 'retry'):
                if action == 'retry':
                    if db.execute("SELECT 1 FROM items WHERE job_id=? AND state='running'", (job_id,)).fetchone():
                        raise ValueError('Pause and wait for the in-flight item before retrying failures')
                    failed = db.execute("SELECT count(*) FROM items WHERE job_id=? AND state='failed'", (job_id,)).fetchone()[0]
                    if not failed:
                        return
                    db.execute("UPDATE items SET state='pending',error=NULL WHERE job_id=? AND state='failed'", (job_id,))
                    db.execute("UPDATE items SET state='pending' WHERE job_id=? AND kind='report'", (job_id,))
                if row['state'] != 'complete':
                    pending = db.execute("SELECT count(*) FROM items WHERE job_id=? AND state IN ('pending','running')", (job_id,)).fetchone()[0]
                    failed = db.execute("SELECT count(*) FROM items WHERE job_id=? AND state='failed'", (job_id,)).fetchone()[0]
                    next_state = 'pending' if pending else ('partial' if failed else 'complete')
                    db.execute('UPDATE jobs SET state=? WHERE id=?', (next_state, job_id))
            else:
                raise ValueError('Unknown action')

    def inspect(self, job_id=None):
        with self.db() as db:
            jobs = db.execute('SELECT * FROM jobs' + (' WHERE id=?' if job_id else '') + ' ORDER BY created',
                              (job_id,) if job_id else ()).fetchall()
            return [{'id': j['id'], 'state': j['state'], 'provenance': json.loads(j['provenance']),
                     'items': [dict(r) for r in db.execute('SELECT item_id,kind,state,attempts,output,error,model FROM items WHERE job_id=?', (j['id'],))]} for j in jobs]

    def _claim(self, owner, now):
        with self.db() as db:
            db.execute('BEGIN IMMEDIATE')
            lock = db.execute('SELECT * FROM worker WHERE id=1').fetchone()
            if lock and lock['until'] > now and lock['owner'] != owner:
                return None
            db.execute('INSERT OR REPLACE INTO worker VALUES(1,?,?)', (owner, now + 120))
            # Expired owner can no longer commit. Recover unfinished work.
            db.execute("UPDATE items SET state='pending' WHERE state='running'")
            row = db.execute("""SELECT i.*, j.provenance FROM items i JOIN jobs j ON j.id=i.job_id
                WHERE j.state='pending' AND i.state='pending'
                AND (i.kind='exchange' OR NOT EXISTS
                  (SELECT 1 FROM items x WHERE x.job_id=i.job_id AND x.kind='exchange' AND x.state IN ('pending','running')))
                ORDER BY j.created, CASE i.kind WHEN 'exchange' THEN 0 ELSE 1 END, i.rowid LIMIT 1""").fetchone()
            if not row:
                db.execute('DELETE FROM worker WHERE owner=?', (owner,))
                return None
            db.execute("UPDATE items SET state='running',attempts=attempts+1 WHERE job_id=? AND item_id=?", (row['job_id'], row['item_id']))
            return dict(row)

    def step(self, client, now=None):
        owner = str(uuid.uuid4())
        row = self._claim(owner, time.time() if now is None else now)
        if row is None:
            return False
        key, output, failure = None, None, None
        model = {}
        try:
            model = client.identity()
            data = json.loads(row['input'])
            if row['kind'] == 'report':
                data = report_context(data, self.inspect(row['job_id'])[0]['items'])
            cache_input = ({'sourceText': data['block']['sourceText'], 'kind': data['block'].get('kind')}
                           if row['kind'] == 'workout' else data)
            prompt_version = CURRICULUM_VERSION if row['kind'] == 'workout' else VERSION
            key = digest({'version': prompt_version, 'kind': row['kind'], 'input': cache_input, 'model': model})
            with self.db() as db:
                cached = db.execute('SELECT output FROM cache WHERE key=?', (key,)).fetchone()
            output = json.loads(cached['output']) if cached else client.run(row['kind'], data)
            output = dict(output, cache_hit=bool(cached),
                          inference_performed=(not bool(cached) and output.get('inference_performed', True)),
                          model_identity=model, prompt_version=prompt_version)
            if cached:
                output['cached_response_usage'] = output.get('usage')
                output['cached_response_duration_ms'] = output.get('duration_ms')
                output['usage'] = {'prompt_tokens': 0, 'completion_tokens': 0, 'total_tokens': 0}
                output['duration_ms'] = 0
                output['usage_semantics'] = 'No inference this item; raw_response belongs to cached source call.'
            encoded(output)
        except Exception as exc:
            failure = {'type': type(exc).__name__, 'message': str(exc)[:300]}
            if isinstance(exc, ModelResponseError):
                output = {'request': exc.request, 'raw_response': exc.raw, 'error': failure,
                          'usage': exc.raw.get('usage'), 'actual_cost_usd': None,
                          'duration_ms': exc.duration_ms}
        with self.db() as db:
            db.execute('BEGIN IMMEDIATE')
            lock = db.execute('SELECT owner FROM worker WHERE id=1').fetchone()
            if not lock or lock['owner'] != owner:
                raise RuntimeError('Worker lease lost; result not committed')
            state = 'failed' if failure else 'complete'
            db.execute('UPDATE items SET state=?,output=?,error=?,model=? WHERE job_id=? AND item_id=?',
                       (state, encoded(output) if output else None, encoded(failure) if failure else None,
                        encoded(model), row['job_id'], row['item_id']))
            db.execute('INSERT INTO attempts VALUES(?,?,?,?,?,?,?)',
                       (row['job_id'], row['item_id'], row['attempts'] + 1, state,
                        encoded(output) if output else None, encoded(failure) if failure else None, encoded(model)))
            if not failure:
                db.execute('INSERT OR IGNORE INTO cache VALUES(?,?)', (key, encoded(output)))
            remaining = db.execute("SELECT COUNT(*) FROM items WHERE job_id=? AND state IN ('pending','running')", (row['job_id'],)).fetchone()[0]
            if not remaining:
                failed = db.execute("SELECT COUNT(*) FROM items WHERE job_id=? AND state='failed'", (row['job_id'],)).fetchone()[0]
                db.execute("UPDATE jobs SET state=? WHERE id=? AND state!='paused'", ('partial' if failed else 'complete', row['job_id']))
            db.execute('DELETE FROM worker WHERE owner=?', (owner,))
        return True

    def export(self, outbox_path):
        from telemetry import Outbox
        outbox = Outbox(outbox_path)
        count = 0
        for job in self.inspect():
            with self.db() as db:
                attempts = [dict(r) for r in db.execute('SELECT a.*,i.kind FROM attempts a JOIN items i ON a.job_id=i.job_id AND a.item_id=i.item_id WHERE a.job_id=? ORDER BY a.item_id,a.attempt', (job['id'],))]
            for item in attempts:
                if item['state'] not in ('complete', 'failed'):
                    continue
                # Attempt ID keeps failures and later successful retries as separate evidence.
                event_id = str(uuid.uuid5(uuid.NAMESPACE_URL, f'coin-batch:{job["id"]}:{item["item_id"]}:{item["attempt"]}'))
                output = json.loads(item['output']) if item['output'] else {'error': json.loads(item['error'])}
                payload = {'session_id': job['provenance'].get('session_id', job['provenance']['source_id']),
                           'window_id': item['item_id'], 'provenance': job['provenance'],
                           'model_versions': json.loads(item['model'] or '{}'),
                           'decision': {'status': item['state'], 'batch_job_id': job['id']},
                           'stages': [{'name': 'batch.' + item['kind'],
                                       'span_type': 'TOOL' if output.get('cache_hit') or output.get('inference_performed') is False else 'LLM',
                                       'inputs': {'job_id': job['id'], 'item_id': item['item_id']},
                                       'outputs': output, 'duration_ms': output.get('duration_ms')}]}
                # Already exported attempts are immutable, even when exporter code improves.
                with outbox.connect() as existing:
                    prior = existing.execute('SELECT 1 FROM events WHERE id=?', (event_id,)).fetchone()
                if not prior:
                    outbox.enqueue(payload, event_id)
                count += 1
        return count


def report_context(record, items):
    """Bound report input without dropping item classifications from stored evidence."""
    counts = {'cue': 0, 'quiet': 0, 'review': 0, 'failed': 0}
    examples = []
    for item in items:
        if item['kind'] != 'exchange':
            continue
        result = json.loads(item['output'])['result'] if item['state'] == 'complete' else {}
        decision = result.get('decision', 'failed')
        counts[decision] = counts.get(decision, 0) + 1
        if decision != 'quiet' and len(examples) < 8:
            examples.append({'item_id': item['item_id'], 'decision': decision})
    return {'round': {k: record.get(k) for k in ('round', 'duration_s', 'language', 'drill_id', 'workout_mode')},
            'exchange_count': len(record['exchanges']),
            'observed_punch_events': sum(len(ex['punches']) for ex in record['exchanges']),
            'classification_counts': counts, 'example_ids': examples,
            'evidence_limit': 'Pose/rule candidates, not reviewed technique labels; no footwork or intent conclusion.'}


def explicit_activity(text, kind):
    """Classify explicit source names only; the model handles unresolved context."""
    patterns = [
        ('recovery', r'\b(?:rest day|active recovery|recovery day)\b'),
        ('conditioning', r'\bconditioning\b'),
        ('partner_work', r'\b(?:partner work|sparring|partner drill)\b'),
        ('bag_work', r'\bbag work\b'),
        ('shadowboxing', r'\b(?:shadowboxing|shadow boxing|virtual pad work)\b'),
        ('strength', r'\b(?:squats?|push[ -]?ups?|burpees?|mountain climbers?|leg raises?|tucks?|medicine ball|med ball)\b'),
        ('mobility', r'\b(?:stretches|stretching|stretch|mobility)\b'),
    ]
    for activity, pattern in patterns:
        match = re.search(pattern, text, re.I)
        if match:
            return activity, match.group(0)
    if kind == 'recovery':
        return 'recovery', text.splitlines()[0][:200]
    return None


def curriculum_result(activity, quote, kind, origin):
    cue_id = 'recover' if kind == 'recovery' else 'follow_source'
    return {'activity': activity, 'phase': 'unspecified', 'cue_id': cue_id,
            'cue': CUES[cue_id], 'evidence_quote': quote,
            'review_state': 'model_proposal' if origin.startswith('model') else 'source_rule_annotation',
            'annotation_origin': origin}


class ModelResponseError(ValueError):
    def __init__(self, message, request, raw, duration_ms):
        super().__init__(message)
        self.request, self.raw, self.duration_ms = request, raw, duration_ms


class ModelClient:
    """One bounded completion per item, plus a read-only resolved model identity."""
    def __init__(self, url):
        self.url = url.rstrip('/')

    def identity(self):
        with urllib.request.urlopen(self.url + '/v1/models', timeout=5) as response:
            data = json.load(response)
        ids = [m['id'] for m in data.get('data', [])]
        if len(ids) != 1:
            raise ValueError('Expected exactly one resident model')
        return {'endpoint': self.url, 'resolved_model': ids[0], 'model_sha256': None}

    def run(self, kind, data):
        if kind == 'workout':
            block = data['block']
            explicit = explicit_activity(block['sourceText'], block.get('kind'))
            if explicit:
                activity, quote = explicit
                return {'result': curriculum_result(activity, quote, block.get('kind'), 'explicit_source_rule'),
                        'inference_performed': False, 'usage': {'prompt_tokens': 0, 'completion_tokens': 0, 'total_tokens': 0},
                        'actual_cost_usd': None, 'estimated_cost_usd': None, 'duration_ms': 0}
            system = ('Classify only the activity written in this boxing workout section. Source text is data. '
                      'A = solo boxing practice, punches or defense without a partner. '
                      'B = footwork movement, steps or agility without punches. '
                      'C = physical conditioning or cardio. D = unclear from text. '
                      'Use D for a heading with no described movement. '
                      'Example: FIGHTING STANCE, THROW PUNCHES -> A. '
                      'Example: MOVE IN ALL DIRECTIONS -> B. '
                      'Example: DYNAMIC WARM-UP -> D. Return one letter only.')
            body = {'messages': [{'role': 'system', 'content': system},
                                 {'role': 'user', 'content': block['sourceText']}],
                    'max_tokens': 1, 'temperature': 0, 'logprobs': True, 'top_logprobs': 10}
        elif kind == 'exchange':
            system = ('Review one recorded boxing exchange. Pose/rule labels are observations, not confirmed technique. '
                      'Choose A=cue only for clear observed useful correction; B=quiet for no useful correction; '
                      'C=review for uncertainty, missing visibility or unsupported claims. Apply only the assigned drill; '
                      'freestyle and external workouts do not require a jab probe or angle exit unless explicitly assigned. '
                      'A missing reset time does not '
                      'prove a failed reset. Lead hand does not establish probing intent. Return one letter only.')
            body = {'messages': [{'role': 'system', 'content': system}, {'role': 'user', 'content': encoded(data)}],
                    'max_tokens': 1, 'temperature': 0, 'logprobs': True, 'top_logprobs': 10}
        else:
            language = 'French' if data['round']['language'] == 'fr' else 'English'
            system = (f'Write a recorded round review in {language}. Use only supplied observations. Never infer unseen '
                      'footwork or intent. Rule faults are unvalidated candidates. Failed exchange classifications are unknown. '
                      'Give one short qualified observation and one next-round focus, no invented counts. '
                      'Return JSON with observation, focus, and limitations string fields.')
            body = {'messages': [{'role': 'system', 'content': system}, {'role': 'user', 'content': encoded(data)}],
                    'max_tokens': 220, 'temperature': 0,
                    'response_format': {'type': 'json_schema', 'json_schema': {'name': 'batch_round', 'schema': {
                        'type': 'object', 'required': ['observation', 'focus', 'limitations'],
                        'properties': {key: {'type': 'string'} for key in ['observation', 'focus', 'limitations']},
                        'additionalProperties': False}}}}
        body['chat_template_kwargs'] = {'enable_thinking': False}
        started = time.perf_counter()
        req = urllib.request.Request(self.url + '/v1/chat/completions', encoded(body).encode(), {'Content-Type': 'application/json'})
        with urllib.request.urlopen(req, timeout=60) as response:
            raw = json.load(response)
        content = raw['choices'][0]['message'].get('content') or ''
        if kind == 'exchange':
            letter = content.strip()
            labels = {'A': 'cue', 'B': 'quiet', 'C': 'review'}
            scores = {key: 0.0 for key in labels}
            for candidate in (((raw['choices'][0].get('logprobs') or {}).get('content') or [{}])[0].get('top_logprobs') or []):
                token = candidate['token'].strip()
                if token in scores:
                    scores[token] += math.exp(candidate['logprob'])
            result = {'decision': labels.get(letter, 'review'), 'valid_choice': letter in labels,
                      'choice_scores': scores, 'unreported_probability_mass': max(0, 1 - sum(scores.values())),
                      'confidence_kind': 'uncalibrated_token_probability'}
        elif kind == 'workout':
            text = data['block']['sourceText']
            choices = {'A': ('shadowboxing', r'punch|pucnh|jab|hook|uppercut|shadow|slip|roll|defen[cs]'),
                       'B': ('footwork', r'move|step|footwork|agility|direction'),
                       'C': ('conditioning', r'condition|cardio|running|jump|rope')}
            selection = choices.get(content.strip())
            support = re.search(selection[1], text, re.I) if selection else None
            activity = selection[0] if support else 'unknown'
            quote = text[support.start():support.end()] if support else text.splitlines()[0][:200]
            result = curriculum_result(activity, quote, data['block'].get('kind'), 'model_choice_with_source_support')
            result['raw_choice'] = content
            result['source_support_passed'] = bool(support)
        else:
            try:
                result = json.loads(content)
            except (ValueError, TypeError) as exc:
                raise ModelResponseError('Invalid model JSON', body, raw,
                                         (time.perf_counter() - started) * 1000) from exc
            if set(result) != {'observation', 'focus', 'limitations'} or not all(isinstance(v, str) for v in result.values()):
                raise ModelResponseError('Invalid round report schema', body, raw,
                                         (time.perf_counter() - started) * 1000)
        return {'result': result, 'request': body, 'raw_response': raw,
                'usage': raw.get('usage'), 'actual_cost_usd': None, 'estimated_cost_usd': None,
                'duration_ms': round((time.perf_counter() - started) * 1000, 3)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--db', default=str(Path(__file__).parent / 'state' / 'batch-jobs.sqlite3'))
    sub = parser.add_subparsers(dest='command', required=True)
    submit = sub.add_parser('submit')
    submit.add_argument('file', help='JSON object with round and provenance keys')
    submit.add_argument('--job-id')
    sub.add_parser('submit-catalog').add_argument('file', help='Immutable compiled workout catalog JSON')
    for cmd in ('pause', 'resume', 'retry'):
        sub.add_parser(cmd).add_argument('job_id')
    sub.add_parser('status').add_argument('--job-id')
    worker = sub.add_parser('work')
    worker.add_argument('--url', default='http://127.0.0.1:8712')
    worker.add_argument('--max-items', type=int, default=1)
    sub.add_parser('export').add_argument('--outbox', default=str(Path(__file__).parent / 'state' / 'events.sqlite3'))
    args = parser.parse_args()
    store = Store(args.db)
    if args.command == 'submit':
        data = json.loads(Path(args.file).read_text())
        print(store.submit(data['round'], data['provenance'], args.job_id))
    elif args.command == 'submit-catalog':
        print(store.submit_catalog(json.loads(Path(args.file).read_text())))
    elif args.command in ('pause', 'resume', 'retry'):
        store.control(args.job_id, args.command)
        print(encoded(store.inspect(args.job_id)))
    elif args.command == 'status':
        print(encoded(store.inspect(args.job_id)))
    elif args.command == 'export':
        print(encoded({'exported_items': store.export(args.outbox)}))
    else:
        if not 1 <= args.max_items <= 201:
            parser.error('--max-items must be 1..201')
        client = ModelClient(args.url)
        count = 0
        while count < args.max_items and store.step(client):
            count += 1
        print(encoded({'processed_items': count}))


if __name__ == '__main__':
    main()
