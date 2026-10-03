"""Bounded, resumable Coin source-French proposal smoke on the resident GB10 9B.

Run with the Coin telemetry venv. This creates a new isolated experiment database;
subsequent runs with --folder resume it. Live Coin traffic has priority. Nothing
from this job is loaded into the app automatically.
"""
import argparse
import hashlib
import json
import os
import shlex
import socket
import subprocess
import sys
import time
import uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / 'outputs/coin/server'))
sys.path.insert(0, '/Users/jaibhagat/code/prismml/outputs/ale-browser-latency/queue')
import gpu_queue
from source_translation_batch import Store, ModelClient, process_one
from telemetry import Outbox
from mlflow_sink import MLflowSink

MODEL_SHA = 'd11d367066813107d56f3d0a67362f934b80407a39d86f5bc216fc30929c831c'
MODEL_NAME = 'Ternary-Bonsai-2-9B-PTQ1_0.gguf'
SSH = ['ssh', '-o', 'BatchMode=yes', '-o', 'ConnectTimeout=5',
       '-o', 'HostName=100.122.5.1', 'gb10']


def live_marker():
    script = ("import pathlib,sqlite3; p=pathlib.Path('/home/chaiwithjai/Documents/code/coin-boxing/state/requests.sqlite3'); "
              "c=sqlite3.connect('file:'+str(p)+'?mode=ro',uri=True); "
              "print(c.execute(\"SELECT count(*) FROM requests WHERE state='running'\").fetchone()[0],p.stat().st_mtime_ns)")
    result = subprocess.run(SSH + ['python3 -c ' + shlex.quote(script)], capture_output=True,
                            text=True, timeout=10, check=True)
    return tuple(map(int, result.stdout.split()))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--folder', type=Path)
    parser.add_argument('--lesson', default='basic-w2-d1')
    parser.add_argument('--limit', type=int, default=4)
    args = parser.parse_args()
    if not 1 <= args.limit <= 30:
        parser.error('limit must be 1..30')
    folder = args.folder or ROOT / 'outputs/batch-source-french' / str(time.time_ns())
    folder.mkdir(parents=True, exist_ok=True)
    catalog_path = ROOT / 'outputs/coin/ios/WorkoutCatalog.json'
    catalog = json.loads(catalog_path.read_text())
    model_identity = f'gb10:8712/{MODEL_NAME}@sha256:{MODEL_SHA}'
    store = Store(folder / 'batch.sqlite')
    job = store.submit_day(catalog, args.lesson, model_identity)
    manifest_path = folder / 'manifest.json'
    manifest = {'jobID': job, 'lessonID': args.lesson,
                'catalogSHA256': hashlib.sha256(catalog_path.read_bytes()).hexdigest(),
                'modelIdentity': model_identity, 'sourceKind': 'catalog_source_item',
                'proposalOnly': True, 'runtimeEligible': False,
                'actualCostUSD': None, 'estimatedCostUSD': None,
                'limits': {'maxItemsThisRun': args.limit, 'concurrency': 1}}
    if manifest_path.exists() and json.loads(manifest_path.read_text())['jobID'] != job:
        raise ValueError('Resume folder refers to another job')
    manifest_path.write_text(json.dumps(manifest, indent=2) + '\n')
    queue_id = 'coin-source-fr-' + job[:16] + '-' + str(time.time_ns())
    gpu_queue.put(queue_id, 'gb10', {'kind': 'existing-service-integration',
                                     'max_items': args.limit, 'manifest': str(manifest_path)})
    if not gpu_queue.claim('gb10', queue_id):
        print(json.dumps({'jobID': job, 'state': 'queue_busy', 'folder': str(folder)}))
        return
    tunnel = None
    outbox = Outbox(folder / 'outbox.sqlite')
    try:
        active, marker = live_marker()
        if active:
            gpu_queue.update(queue_id, 'completed', 'Yielded to live Coin request')
            print(json.dumps({'jobID': job, 'state': 'live_busy', 'folder': str(folder)}))
            return
        with socket.socket() as sock:
            sock.bind(('127.0.0.1', 0))
            port = sock.getsockname()[1]
        tunnel = subprocess.Popen(['ssh', '-N', '-o', 'BatchMode=yes',
            '-o', 'ExitOnForwardFailure=yes', '-o', 'HostName=100.122.5.1',
            '-L', f'127.0.0.1:{port}:127.0.0.1:8712', 'gb10'],
            stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
        endpoint = f'http://127.0.0.1:{port}'
        import urllib.request
        for _ in range(30):
            try:
                models = json.load(urllib.request.urlopen(endpoint + '/v1/models', timeout=2))
                ids = [model['id'] for model in models['data']]
                if len(ids) != 1 or not ids[0].endswith(MODEL_NAME):
                    raise ValueError('Resident model changed')
                break
            except (OSError, TimeoutError):
                if tunnel.poll() is not None:
                    raise RuntimeError('SSH tunnel failed')
                time.sleep(.2)
        else:
            raise RuntimeError('Model endpoint unavailable')
        client = ModelClient(endpoint + '/v1/chat/completions', ids[0])
        processed = []
        for _ in range(args.limit):
            busy, latest = live_marker()
            if busy or latest != marker:
                break
            start = time.monotonic()
            result = process_one(store, job, client)
            if result is None:
                break
            item = result['item']
            duration = (time.monotonic() - start) * 1000
            with store.db() as db:
                row = db.execute('SELECT state,proposal,error,attempts FROM items WHERE job_id=? AND item_key=?',
                                 (job, json.dumps([item['blockID'], item['sourceItemID']],
                                                  ensure_ascii=False, separators=(',', ':')))).fetchone()
            payload = {'session_id': 'source-translation-' + args.lesson,
                       'window_id': item['sourceItemID'], 'captured_at': None,
                       'model_versions': {'translation': model_identity},
                       'decision': {'state': result['state'], 'runtimeEligible': False,
                                    'sourceTextSHA256': item['sourceTextSHA256']},
                       'stages': [{'name': 'source_translation_proposal', 'span_type': 'LLM',
                                   'inputs': {'lessonID': args.lesson, 'blockID': item['blockID'],
                                              'sourceItemID': item['sourceItemID'],
                                              'sourceTextSHA256': item['sourceTextSHA256']},
                                   'outputs': {'state': row['state'], 'proposal': json.loads(row['proposal']) if row['proposal'] else None,
                                               'error': row['error'], 'usage': result.get('usage'),
                                               'actualCostUSD': None, 'estimatedCostUSD': None},
                                   'duration_ms': duration}]}
            event_id = str(uuid.uuid5(uuid.NAMESPACE_URL, job + ':' + item['blockID'] + ':' + item['sourceItemID'] + ':' + str(row['attempts'])))
            outbox.enqueue(payload, event_id)
            processed.append({'sourceItemID': item['sourceItemID'], 'state': result['state'],
                              'durationMs': round(duration, 1)})
            if result['state'] == 'failed':
                break
        sink = MLflowSink('http://127.0.0.1:5210')
        while outbox.counts().get('pending', 0):
            if not outbox.deliver_one(sink):
                break
        status = {'jobID': job, 'folder': str(folder), 'processed': processed,
                  'batch': store.status(job), 'outbox': outbox.counts(),
                  'runtimeEligible': False, 'actualCostUSD': None,
                  'estimatedCostUSD': None}
        (folder / 'result.json').write_text(json.dumps(status, ensure_ascii=False, indent=2) + '\n')
        gpu_queue.update(queue_id, 'completed', 'Bounded source translation proposal pass finished')
        print(json.dumps(status, ensure_ascii=False))
    except BaseException:
        gpu_queue.update(queue_id, 'needs_review', 'Inspect exact request and DB before retry')
        raise
    finally:
        if tunnel is not None:
            tunnel.terminate()
            try: tunnel.wait(timeout=5)
            except subprocess.TimeoutExpired:
                tunnel.kill(); tunnel.wait()


if __name__ == '__main__':
    main()
