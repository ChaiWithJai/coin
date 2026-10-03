"""Read-only audit of one newly completed source-item worker slice.

The baseline is the total complete-item count recorded immediately before a
bounded worker starts.  The auditor identifies the newly completed items from
their latest successful attempt rowids.  It never writes to the batch DB and
does not treat pending work, null cost, or analyst fixtures as approvals.
"""
import argparse
import json
import re
import sqlite3
from pathlib import Path

from batch_jobs import (SOURCE_ITEM_VERSION, catalog_source_item_manifest,
                        explicit_parent_activity)


IDENTITY_FIELDS = (
    'proposal_id', 'workout_id', 'catalog_sha256', 'source_sha256',
    'source_block_id', 'source_item_id', 'source_text', 'source_text_sha256',
    'source_block_text', 'source_block_text_sha256', 'source_url',
    'reference_urls', 'demo_urls', 'source_kind', 'normalization_version',
    'evidence_status',
)
TOKEN_FIELDS = ('prompt_tokens', 'completion_tokens', 'total_tokens')
COST_FIELDS = ('actual_cost_usd', 'estimated_cost_usd')


def _issue(code, item_id=None, detail=None):
    value = {'code': code}
    if item_id is not None:
        value['item_id'] = item_id
    if detail is not None:
        value['detail'] = detail
    return value


def _cost_summary(outputs, field):
    values = [output.get(field) for output in outputs]
    numeric = [value for value in values
               if isinstance(value, (int, float)) and not isinstance(value, bool)]
    invalid = [value for value in values
               if value is not None and not (isinstance(value, (int, float))
                                              and not isinstance(value, bool))]
    return {'null_count': sum(value is None for value in values),
            'non_null_count': len(numeric),
            'sum_usd': sum(numeric) if numeric else None,
            'invalid_count': len(invalid)}


def _read_fixture(path):
    if path is None:
        return []
    payload = json.loads(Path(path).read_text())
    corrections = payload.get('corrections')
    if not isinstance(corrections, list):
        raise ValueError('Analyst fixture must contain a corrections list')
    return corrections


def audit_source_item_slice(database, job_id, baseline_complete,
                            expected_size=201, analyst_fixture=None):
    """Audit a bounded slice and the population-level regression sentinels."""
    if baseline_complete < 0:
        raise ValueError('baseline_complete must be non-negative')
    if expected_size is not None and expected_size < 1:
        raise ValueError('expected_size must be positive or None')

    uri = Path(database).resolve().as_uri() + '?mode=ro'
    db = sqlite3.connect(uri, uri=True)
    db.row_factory = sqlite3.Row
    try:
        job = db.execute('SELECT * FROM jobs WHERE id=?', (job_id,)).fetchone()
        if not job:
            raise ValueError('Unknown job')
        catalog = json.loads(job['input'])
        provenance = json.loads(job['provenance'])
        manifest, proposals = catalog_source_item_manifest(catalog)
        expected = {'source-item:' + p['proposal_id']: p for p in proposals}
        rows = db.execute('''SELECT rowid,item_id,kind,input,state,attempts,output,
                                    error,model
                             FROM items WHERE job_id=? ORDER BY rowid''',
                          (job_id,)).fetchall()
        latest_attempts = db.execute('''
            SELECT i.item_id, MAX(a.rowid) AS completed_attempt_rowid
              FROM items i JOIN attempts a
                ON a.job_id=i.job_id AND a.item_id=i.item_id
             WHERE i.job_id=? AND i.state='complete' AND i.output IS NOT NULL
               AND a.state='complete'
             GROUP BY i.item_id
             ORDER BY completed_attempt_rowid DESC''', (job_id,)).fetchall()
    finally:
        db.close()

    issues = []
    state_counts = {state: 0 for state in ('complete', 'pending', 'running', 'failed')}
    for row in rows:
        state_counts[row['state']] = state_counts.get(row['state'], 0) + 1
    complete_count = state_counts.get('complete', 0)
    delta = complete_count - baseline_complete
    if delta < 0:
        issues.append(_issue('baseline_exceeds_current_complete',
                             detail={'baseline': baseline_complete,
                                     'current': complete_count}))
        delta = 0
    if expected_size is not None and delta != expected_size:
        issues.append(_issue('slice_size_mismatch', detail={
            'baseline_complete': baseline_complete, 'current_complete': complete_count,
            'expected_size': expected_size, 'actual_size': delta}))

    selected_ids = {row['item_id'] for row in latest_attempts[:delta]}
    if len(selected_ids) != delta:
        issues.append(_issue('slice_attempt_history_incomplete', detail={
            'expected': delta, 'selected': len(selected_ids)}))
    slice_rows = [row for row in rows if row['item_id'] in selected_ids]
    if len(slice_rows) != delta:
        issues.append(_issue('slice_item_selection_incomplete', detail={
            'expected': delta, 'selected': len(slice_rows)}))

    parsed = {}
    for row in rows:
        if row['state'] != 'complete' or not row['output']:
            continue
        try:
            parsed[row['item_id']] = (json.loads(row['input']), json.loads(row['output']))
        except (TypeError, json.JSONDecodeError) as exc:
            issues.append(_issue('invalid_completed_item_json', row['item_id'], str(exc)))

    slice_counts = {'processed_items': len(slice_rows), 'inference_calls': 0,
                    'cache_materializations': 0, 'deterministic_results': 0}
    usage = {field: 0 for field in TOKEN_FIELDS}
    slice_outputs = []
    identity_checked = exact_quotes_checked = 0
    for row in slice_rows:
        pair = parsed.get(row['item_id'])
        if not pair:
            continue
        source, output = pair
        slice_outputs.append(output)
        result = output.get('result')
        if not isinstance(result, dict):
            issues.append(_issue('missing_result', row['item_id']))
            continue
        authoritative = expected.get(row['item_id'])
        if authoritative is None or source != authoritative:
            issues.append(_issue('slice_input_not_manifest_proposal', row['item_id']))
        identity_checked += 1
        for field in IDENTITY_FIELDS:
            if result.get(field) != source.get(field):
                issues.append(_issue('source_identity_mismatch', row['item_id'], {
                    'field': field, 'expected': source.get(field),
                    'actual': result.get(field)}))
        if result.get('runtime_eligible') is not False:
            issues.append(_issue('runtime_eligible_not_false', row['item_id'],
                                 result.get('runtime_eligible')))
        if result.get('review_state') in ('approved', 'promoted', 'runtime'):
            issues.append(_issue('promoted_review_state', row['item_id'],
                                 result.get('review_state')))
        if result.get('activity') != 'unknown':
            exact_quotes_checked += 1
            quote = result.get('evidence_quote')
            text = source.get('source_text', '')
            if not isinstance(quote, str) or not quote.strip() or quote.casefold() not in text.casefold():
                issues.append(_issue('known_result_without_exact_source_quote',
                                     row['item_id'], quote))

        item_usage = output.get('usage')
        if not isinstance(item_usage, dict):
            issues.append(_issue('missing_usage', row['item_id']))
            item_usage = {}
        for field in TOKEN_FIELDS:
            value = item_usage.get(field)
            if not isinstance(value, int) or isinstance(value, bool) or value < 0:
                issues.append(_issue('invalid_usage', row['item_id'],
                                     {'field': field, 'value': value}))
            else:
                usage[field] += value
        if all(isinstance(item_usage.get(field), int) for field in TOKEN_FIELDS):
            if item_usage['total_tokens'] != item_usage['prompt_tokens'] + item_usage['completion_tokens']:
                issues.append(_issue('usage_total_mismatch', row['item_id'], item_usage))

        cache_hit = output.get('cache_hit') is True
        inference = output.get('inference_performed') is True
        if cache_hit:
            slice_counts['cache_materializations'] += 1
            if inference or any(item_usage.get(field) != 0 for field in TOKEN_FIELDS):
                issues.append(_issue('cache_usage_not_zero', row['item_id'], item_usage))
            if output.get('cache_materialization') != 'model_decision_only_current_source_identity':
                issues.append(_issue('cache_rebinding_marker_missing', row['item_id']))
        elif inference:
            slice_counts['inference_calls'] += 1
        else:
            slice_counts['deterministic_results'] += 1
            if any(item_usage.get(field) != 0 for field in TOKEN_FIELDS):
                issues.append(_issue('deterministic_usage_not_zero', row['item_id'], item_usage))

    for field in COST_FIELDS:
        summary = _cost_summary(slice_outputs, field)
        if summary['invalid_count']:
            issues.append(_issue('invalid_cost_value', detail={'field': field,
                                                               **summary}))

    # These sentinels cover the whole completed population because most are
    # deterministic and may predate the worker baseline.
    corrections = _read_fixture(analyst_fixture)
    proposals_by_stable_source = {}
    for proposal in proposals:
        key = (proposal.get('source_block_id'), proposal.get('source_item_id'),
               proposal.get('source_text'))
        proposals_by_stable_source.setdefault(key, []).append(proposal)
    correction_results = []
    for fixture in corrections:
        fixture_proposal_id = fixture.get('proposal_id')
        item_id = ('source-item:' + fixture_proposal_id
                   if isinstance(fixture_proposal_id, str) else None)
        resolution = 'proposal_id'
        if item_id not in parsed:
            stable_key = (fixture.get('source_block_id'), fixture.get('source_item_id'),
                          fixture.get('exact_source_text'))
            matches = proposals_by_stable_source.get(stable_key, [])
            if len(matches) == 1:
                item_id = 'source-item:' + matches[0]['proposal_id']
                resolution = 'stable_source_identity'
            elif not matches:
                item_id = None
                resolution = 'not_found'
            else:
                item_id = None
                resolution = 'ambiguous_stable_source_identity'
        pair = parsed.get(item_id)
        actual = pair[1].get('result', {}).get('activity') if pair else None
        passed = actual == fixture.get('proposed_activity')
        correction_results.append({'fixture_proposal_id': fixture_proposal_id,
                                   'resolved_item_id': item_id,
                                   'resolution': resolution,
                                   'expected': fixture.get('proposed_activity'),
                                   'actual': actual, 'passed': passed})
        if not passed:
            issues.append(_issue('analyst_fixture_mismatch', item_id or fixture_proposal_id,
                                 correction_results[-1]))

    virtual_results = []
    child_results = []
    for proposal in proposals:
        item_id = 'source-item:' + proposal['proposal_id']
        pair = parsed.get(item_id)
        actual = pair[1].get('result', {}).get('activity') if pair else None
        if re.search(r'\b(?:virtual|virual) sparring\b', proposal.get('source_text', ''), re.I):
            passed = actual == 'shadowboxing'
            virtual_results.append({'item_id': item_id, 'actual': actual,
                                    'passed': passed})
            if not passed:
                issues.append(_issue('virtual_sparring_regression', item_id, actual))
        parent = explicit_parent_activity(proposal.get('source_block_text', ''))
        if (parent and proposal.get('annotation_origin') == 'explicit_source_rule'
                and proposal.get('activity') in ('conditioning', 'strength', 'mobility')):
            passed = actual == proposal['activity']
            child_results.append({'item_id': item_id, 'expected': proposal['activity'],
                                  'actual': actual, 'passed': passed})
            if not passed:
                issues.append(_issue('explicit_child_modality_regression', item_id,
                                     child_results[-1]))

    costs = {field: _cost_summary(slice_outputs, field) for field in COST_FIELDS}
    return {
        'schema_version': 1,
        'audit_kind': 'bounded_source_item_slice',
        'job_id': job_id,
        'job_state': job['state'],
        'passed': not issues,
        'baseline_complete': baseline_complete,
        'normalization_version': SOURCE_ITEM_VERSION,
        'catalog_sha256': manifest['catalog_sha256'],
        'source_item_manifest_sha256': manifest['manifest_sha256'],
        'provenance': {
            'origin': provenance.get('origin'),
            'source_id': provenance.get('source_id'),
            'runtime_promotion': provenance.get('runtime_promotion'),
        },
        'queue': {'items': len(rows), **state_counts},
        'slice': {**slice_counts, 'item_ids': sorted(selected_ids),
                  'source_identity_checked': identity_checked,
                  'known_exact_quotes_checked': exact_quotes_checked,
                  'usage': usage, 'costs': costs},
        'regression_sentinels': {
            'analyst_corrections': {'checked': len(correction_results),
                                    'passed': sum(x['passed'] for x in correction_results),
                                    'items': correction_results},
            'virtual_or_virual_sparring': {'checked': len(virtual_results),
                                           'passed': sum(x['passed'] for x in virtual_results),
                                           'items': virtual_results},
            'explicit_child_modality': {'checked': len(child_results),
                                        'passed': sum(x['passed'] for x in child_results),
                                        'items': child_results},
        },
        'runtime_eligibility': {'required': False,
                                'promotion_performed': False},
        'issues': issues,
    }


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--db', required=True, type=Path)
    parser.add_argument('--job', required=True)
    parser.add_argument('--baseline-complete', required=True, type=int)
    parser.add_argument('--expected-size', type=int, default=201)
    parser.add_argument('--analyst-fixture', type=Path)
    parser.add_argument('--output', type=Path)
    args = parser.parse_args(argv)
    report = audit_source_item_slice(args.db, args.job, args.baseline_complete,
                                     args.expected_size, args.analyst_fixture)
    body = json.dumps(report, indent=2, sort_keys=True) + '\n'
    if args.output:
        args.output.write_text(body)
    else:
        print(body, end='')
    return 0 if report['passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
