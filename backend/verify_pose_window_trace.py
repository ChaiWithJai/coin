"""Synthetic HTTP -> durable outbox -> MLflow verification. No camera inference."""
import json
import os
import tempfile
import uuid
import asyncio
from pathlib import Path

from telemetry import Outbox
from mlflow_sink import MLflowSink


async def post(app, path, body, authorization=None):
    payload = json.dumps(body).encode()
    headers = [(b'content-type', b'application/json')]
    if authorization:
        headers.append((b'authorization', authorization.encode()))
    scope = {'type': 'http', 'asgi': {'version': '3.0'}, 'method': 'POST',
             'scheme': 'http', 'path': path, 'raw_path': path.encode(),
             'query_string': b'', 'root_path': '', 'headers': headers,
             'server': ('localhost', 80), 'client': ('fixture', 0)}
    sent = []
    received = False

    async def receive():
        nonlocal received
        if not received:
            received = True
            return {'type': 'http.request', 'body': payload, 'more_body': False}
        return {'type': 'http.disconnect'}

    async def send(message):
        sent.append(message)

    await app(scope, receive, send)
    status = next(message['status'] for message in sent if message['type'] == 'http.response.start')
    content = b''.join(message.get('body', b'') for message in sent if message['type'] == 'http.response.body')
    return status, json.loads(content)


with tempfile.TemporaryDirectory(prefix='coin-pose-verification-') as temporary:
    root = Path(temporary)
    token = 'fixture-' + uuid.uuid4().hex
    token_file = root / 'token'
    token_file.write_text(token)
    os.environ['COIN_TOKEN_FILE'] = str(token_file)
    import service

    service.DATA = root
    service.OUTBOX = Outbox(root / 'events.sqlite3')
    sample_id = uuid.uuid4()
    session_id = uuid.uuid4()
    body = {
        'request_id': str(sample_id), 'session_id': str(session_id),
        'block_id': str(uuid.uuid4()), 'sequence': 1,
        'sampled_at_ms': 1_700_000_000_000, 'language': 'fr',
        'landmark_count': 33, 'visible_landmark_count': 12,
        'framing_ready': False, 'capture_to_pose_ms': 38.5,
        'wrist_travel_body_widths': 0.42,
        'source_version': 'mediapipe-pose-full-v1',
    }
    denied_status, _ = asyncio.run(post(service.app, '/v1/live/pose-window', body))
    assert denied_status == 401
    status, result = asyncio.run(post(service.app, '/v1/live/pose-window', body,
                                      authorization='Bearer ' + token))
    assert status == 200, result
    assert result['event_id'] == str(sample_id)
    assert result['action'] == 'silence'
    assert service.OUTBOX.counts() == {'pending': 1}

    sink = MLflowSink()
    assert service.OUTBOX.deliver_one(sink)
    runs = sink.client.search_runs([sink.experiment.experiment_id],
                                   filter_string=f"tags.event_id = '{sample_id}' and attributes.status = 'FINISHED'",
                                   max_results=1)
    assert len(runs) == 1
    trace_id = runs[0].data.tags['trace_id']
    trace = sink.client.get_trace(trace_id)
    names = {span.name for span in trace.data.spans}
    assert {'coaching_event', 'visual_perception'} <= names
    visual = next(span for span in trace.data.spans if span.name == 'visual_perception')
    assert visual.outputs['wrist_travel_body_widths'] == 0.42
    print(json.dumps({
        'scope': 'synthetic pose aggregate; no physical camera or movement inference',
        'event_id': str(sample_id), 'session_id': str(session_id),
        'mlflow_run_id': runs[0].info.run_id, 'trace_id': trace_id,
        'spans': sorted(names), 'outbox': service.OUTBOX.counts(),
        'action': result['action'], 'wrist_travel_body_widths': visual.outputs['wrist_travel_body_widths'],
    }))
