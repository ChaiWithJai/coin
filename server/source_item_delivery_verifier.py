"""Read-only reconciliation of batch attempts, the durable outbox, and MLflow.

The verifier never exports, delivers, retries, or edits evidence.  MLflow access is
injected so tests and offline audits do not need a tracking server.
"""
import json
import sqlite3
import uuid
import argparse
from collections import Counter, defaultdict
from contextlib import closing
from pathlib import Path


def attempt_event_id(job_id, item_id, attempt):
    return str(uuid.uuid5(uuid.NAMESPACE_URL,
                          f'coin-batch:{job_id}:{item_id}:{attempt}'))


def _readonly(path):
    return sqlite3.connect(f'file:{Path(path).resolve()}?mode=ro', uri=True)


def expected_attempts(batch_path, job_id):
    """Return immutable terminal attempts and separately count unfinished items."""
    with closing(_readonly(batch_path)) as db:
        exists = db.execute('SELECT 1 FROM jobs WHERE id=?', (job_id,)).fetchone()
        if not exists:
            raise ValueError(f'Unknown job: {job_id}')
        attempts = db.execute(
            """SELECT a.item_id,a.attempt,a.state
               FROM attempts a WHERE a.job_id=? AND a.state IN ('complete','failed')
               ORDER BY a.item_id,a.attempt""", (job_id,)).fetchall()
        item_states = dict(db.execute(
            'SELECT state,count(*) FROM items WHERE job_id=? GROUP BY state',
            (job_id,)).fetchall())
    records = [{'item_id': item, 'attempt': attempt, 'attempt_state': state,
                'event_id': attempt_event_id(job_id, item, attempt)}
               for item, attempt, state in attempts]
    return records, {
        'pending': item_states.get('pending', 0),
        'running': item_states.get('running', 0),
        'complete': item_states.get('complete', 0),
        'failed': item_states.get('failed', 0),
    }


def _outbox_records(outbox_path, event_ids):
    wanted = set(event_ids)
    found = {}
    with closing(_readonly(outbox_path)) as db:
        for event_id, payload, state, last_error in db.execute(
                'SELECT id,payload,state,last_error FROM events'):
            if event_id in wanted:
                found[event_id] = {'state': state, 'last_error': last_error,
                                   'payload': json.loads(payload)}
    return found


def _coverage(payload):
    decision = payload.get('decision') if isinstance(payload, dict) else None
    stages = payload.get('stages') if isinstance(payload, dict) else None
    decision = decision if isinstance(decision, dict) else {}
    stages = stages if isinstance(stages, list) else []
    by_name = {s.get('name'): s for s in stages if isinstance(s, dict)}
    normalization = by_name.get('source_item.normalization', {})
    norm_outputs = normalization.get('outputs', {})
    attempt = norm_outputs.get('attempt', {}) if isinstance(norm_outputs, dict) else {}
    lineage = norm_outputs.get('source_lineage', {}) if isinstance(norm_outputs, dict) else {}
    gate = by_name.get('source_item.gate_decision', {}).get('outputs', {})
    review = by_name.get('source_item.human_review', {}).get('outputs', {})
    promotion = by_name.get('source_item.promotion_decision', {}).get('outputs', {})
    kind = attempt.get('attempt_kind')
    kind_stage = {'model_call': 'source_item.model_inference',
                  'cache_materialization': 'source_item.cache_materialization'}.get(kind)
    usage = attempt.get('usage')
    cost_status = attempt.get('cost_status')
    return {
        'schema': decision.get('telemetry_schema_version') == 'source-item-attempt-v1',
        'lineage': (normalization.get('inputs', {}).get('job_id') is not None and
                    normalization.get('inputs', {}).get('item_id') is not None and
                    bool(lineage.get('source_item_id')) and
                    bool(lineage.get('normalization_version'))),
        'runtime_gate': (decision.get('runtime_eligible') is False and
                         decision.get('runtime_promotion') is False and
                         gate.get('runtime_promotion') is False and
                         review.get('state') == 'not_performed' and
                         promotion.get('decision') == 'not_promoted'),
        'usage': (kind in ('deterministic_rule', 'model_call', 'cache_materialization') and
                  isinstance(usage, dict) and 'total_tokens' in usage and
                  (kind_stage is None or kind_stage in by_name)),
        'cost': (isinstance(cost_status, dict) and
                 cost_status.get('actual') in ('recorded', 'unknown') and
                 cost_status.get('estimated') in ('recorded', 'unknown') and
                 'actual_cost_usd' in attempt and 'estimated_cost_usd' in attempt),
    }


def _summarize_coverage(payload_by_id, expected_ids):
    result = {}
    for field in ('schema', 'lineage', 'runtime_gate', 'usage', 'cost'):
        missing = [event_id for event_id in expected_ids
                   if not _coverage(payload_by_id.get(event_id, {}))[field]]
        result[field] = {'covered': len(expected_ids) - len(missing),
                         'total': len(expected_ids), 'missing_event_ids': missing}
    return result


def verify_delivery(batch_path, outbox_path, job_id, mlflow_reader,
                    experiment_id='40'):
    """Reconcile one job. ``mlflow_reader`` returns run dicts for event IDs.

    Each run dict contains event_id, status, trace_id, and the parsed event.json
    payload. Multiple rows with the same event_id are intentionally retained so
    at-least-once delivery duplicates are visible.
    """
    attempts, item_states = expected_attempts(batch_path, job_id)
    expected_ids = [row['event_id'] for row in attempts]
    outbox = _outbox_records(outbox_path, expected_ids)
    outbox_groups = {'queued': [], 'delivered': [], 'failed': [], 'missing': []}
    for event_id in expected_ids:
        row = outbox.get(event_id)
        if row is None:
            outbox_groups['missing'].append(event_id)
        elif row['state'] == 'delivered':
            outbox_groups['delivered'].append(event_id)
        elif row['state'] == 'failed':
            outbox_groups['failed'].append(event_id)
        else:
            outbox_groups['queued'].append(event_id)

    runs = list(mlflow_reader(str(experiment_id), expected_ids))
    by_event = defaultdict(list)
    expected_set = set(expected_ids)
    for run in runs:
        if run.get('event_id') in expected_set:
            by_event[run['event_id']].append(run)
    finished = {event_id: [r for r in rows if r.get('status') == 'FINISHED']
                for event_id, rows in by_event.items()}
    missing_finished = [event_id for event_id in expected_ids
                        if not finished.get(event_id)]
    duplicate_traces = {
        event_id: [r.get('trace_id') for r in rows]
        for event_id, rows in finished.items() if len(rows) > 1
    }
    mlflow_payloads = {
        event_id: rows[0].get('payload', {}) for event_id, rows in finished.items()
        if rows
    }
    outbox_payloads = {event_id: row['payload'] for event_id, row in outbox.items()}
    return {
        'job_id': job_id, 'experiment_id': str(experiment_id),
        'expected_attempt_count': len(attempts),
        'attempt_states': dict(Counter(a['attempt_state'] for a in attempts)),
        'job_items': item_states,
        'pending_job_items': item_states['pending'] + item_states['running'],
        'outbox': {name: {'count': len(ids), 'event_ids': ids}
                   for name, ids in outbox_groups.items()},
        'mlflow': {
            'finished': {'count': len(expected_ids) - len(missing_finished),
                         'event_ids': [e for e in expected_ids if e not in missing_finished]},
            'missing': {'count': len(missing_finished),
                        'event_ids': missing_finished},
            'duplicate_traces': {'count': len(duplicate_traces),
                                 'events': duplicate_traces},
        },
        'outbox_coverage': _summarize_coverage(outbox_payloads, expected_ids),
        'mlflow_coverage': _summarize_coverage(mlflow_payloads, expected_ids),
    }


class MLflowRunReader:
    """Small read-only adapter around an MlflowClient-like object."""
    def __init__(self, client):
        self.client = client

    def __call__(self, experiment_id, event_ids):
        rows = []
        for event_id in event_ids:
            runs = self.client.search_runs(
                [str(experiment_id)], filter_string=f"tags.event_id = '{event_id}'")
            for run in runs:
                run_id = run.info.run_id
                try:
                    local = self.client.download_artifacts(run_id, 'event.json')
                    payload = json.loads(Path(local).read_text())
                except Exception:
                    payload = {}
                rows.append({'event_id': event_id, 'status': run.info.status,
                             'trace_id': run.data.tags.get('trace_id'),
                             'run_id': run_id, 'payload': payload})
        return rows


def main(argv=None):
    parser = argparse.ArgumentParser(
        description='Read-only source-item delivery reconciliation')
    parser.add_argument('--batch', required=True)
    parser.add_argument('--outbox', required=True)
    parser.add_argument('--job-id', required=True)
    parser.add_argument('--tracking-uri', default='http://127.0.0.1:5210')
    parser.add_argument('--experiment-id', default='40')
    args = parser.parse_args(argv)
    from mlflow import MlflowClient
    report = verify_delivery(
        args.batch, args.outbox, args.job_id,
        MLflowRunReader(MlflowClient(tracking_uri=args.tracking_uri)),
        args.experiment_id)
    print(json.dumps(report, sort_keys=True, indent=2))
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
