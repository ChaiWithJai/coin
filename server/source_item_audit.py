"""Read-only audit for a completed atomic source-item batch job.

The audit proves queue completeness, source identity, cache rebinding, usage
accounting, and fail-closed runtime eligibility.  Its semantic sample is a
stable review set of source-supported, non-unknown proposals; inclusion in the
sample is not an approval or a claim that the classification is correct.
"""
import argparse
import hashlib
import json
import sqlite3
from pathlib import Path

from batch_jobs import SOURCE_ITEM_VERSION, catalog_source_item_manifest


IDENTITY_FIELDS = (
    'proposal_id', 'workout_id', 'catalog_sha256', 'source_sha256',
    'source_block_id', 'source_item_id', 'source_text', 'source_text_sha256',
    'source_block_text', 'source_block_text_sha256',
    'source_url', 'reference_urls', 'demo_urls', 'source_kind',
    'normalization_version', 'evidence_status',
)
TOKEN_FIELDS = ('prompt_tokens', 'completion_tokens', 'total_tokens')


def _issue(code, item_id=None, detail=None):
    issue = {'code': code}
    if item_id is not None:
        issue['item_id'] = item_id
    if detail is not None:
        issue['detail'] = detail
    return issue


def _stable_sample(candidates, limit, seed):
    ranked = sorted(candidates, key=lambda item: hashlib.sha256(
        (seed + '\0' + item['proposal_id']).encode()).hexdigest())
    return ranked[:limit]


def audit_source_item_job(database, job_id, sample_size=40):
    """Return a deterministic JSON-serializable audit without mutating the DB."""
    if sample_size < 0:
        raise ValueError('sample_size must be non-negative')
    uri = Path(database).resolve().as_uri() + '?mode=ro'
    db = sqlite3.connect(uri, uri=True)
    db.row_factory = sqlite3.Row
    try:
        job = db.execute('SELECT * FROM jobs WHERE id=?', (job_id,)).fetchone()
        if not job:
            raise ValueError('Unknown job')
        catalog, provenance = json.loads(job['input']), json.loads(job['provenance'])
        manifest, proposals = catalog_source_item_manifest(catalog)
        expected = {'source-item:' + p['proposal_id']: p for p in proposals}
        rows = db.execute('''SELECT item_id,kind,input,state,attempts,output,error,model
                             FROM items WHERE job_id=? ORDER BY item_id''',
                          (job_id,)).fetchall()
    finally:
        db.close()

    issues = []
    if job['state'] != 'complete':
        issues.append(_issue('job_not_complete', detail=job['state']))
    if provenance.get('origin') != 'source_curriculum':
        issues.append(_issue('wrong_provenance_origin', detail=provenance.get('origin')))
    expected_provenance = {
        'catalog_sha256': manifest['catalog_sha256'],
        'source_item_manifest_sha256': manifest['manifest_sha256'],
        'source_item_count': manifest['source_item_count'],
        'source_sha256': manifest['source_sha256'],
        'annotation_version': SOURCE_ITEM_VERSION,
        'runtime_promotion': False,
    }
    for field, value in expected_provenance.items():
        if provenance.get(field) != value:
            issues.append(_issue('provenance_mismatch', detail={'field': field,
                                                                 'expected': value,
                                                                 'actual': provenance.get(field)}))

    actual_ids = {row['item_id'] for row in rows}
    for missing in sorted(set(expected) - actual_ids):
        issues.append(_issue('missing_item', missing))
    for extra in sorted(actual_ids - set(expected)):
        issues.append(_issue('extra_item', extra))

    counts = {'items': len(rows), 'complete': 0, 'failed': 0, 'pending': 0,
              'inference_calls': 0, 'cache_materializations': 0,
              'deterministic_results': 0, 'known_proposals': 0,
              'unknown_proposals': 0}
    usage = {key: 0 for key in TOKEN_FIELDS}
    semantic_candidates = []
    for row in rows:
        item_id = row['item_id']
        if row['kind'] != 'source_item':
            issues.append(_issue('wrong_item_kind', item_id, row['kind']))
        if row['state'] != 'complete' or not row['output']:
            counts[row['state'] if row['state'] in ('failed', 'pending') else 'pending'] += 1
            issues.append(_issue('item_not_complete', item_id, row['state']))
            continue
        counts['complete'] += 1
        try:
            source, output = json.loads(row['input']), json.loads(row['output'])
        except (TypeError, json.JSONDecodeError) as exc:
            issues.append(_issue('invalid_item_json', item_id, str(exc)))
            continue
        result = output.get('result')
        if not isinstance(result, dict):
            issues.append(_issue('missing_result', item_id))
            continue
        authoritative = expected.get(item_id)
        if authoritative is None:
            continue
        if source != authoritative:
            issues.append(_issue('item_input_not_manifest_proposal', item_id))
        for field in IDENTITY_FIELDS:
            if result.get(field) != source.get(field):
                issues.append(_issue('result_source_identity_mismatch', item_id,
                                     {'field': field, 'expected': source.get(field),
                                      'actual': result.get(field)}))
        if result.get('runtime_eligible') is not False:
            issues.append(_issue('runtime_eligible_not_false', item_id,
                                 result.get('runtime_eligible')))
        if result.get('review_state') in ('approved', 'promoted', 'runtime'):
            issues.append(_issue('promoted_review_state', item_id,
                                 result.get('review_state')))

        item_usage = output.get('usage')
        if not isinstance(item_usage, dict):
            issues.append(_issue('missing_usage', item_id))
            item_usage = {}
        for field in TOKEN_FIELDS:
            value = item_usage.get(field)
            if not isinstance(value, int) or isinstance(value, bool) or value < 0:
                issues.append(_issue('invalid_usage', item_id,
                                     {'field': field, 'value': value}))
            else:
                usage[field] += value
        if all(isinstance(item_usage.get(k), int) for k in TOKEN_FIELDS):
            if item_usage.get('total_tokens') != (item_usage.get('prompt_tokens', 0)
                                                   + item_usage.get('completion_tokens', 0)):
                issues.append(_issue('usage_total_mismatch', item_id, item_usage))

        cache_hit = output.get('cache_hit') is True
        inference = output.get('inference_performed') is True
        if cache_hit:
            counts['cache_materializations'] += 1
            if output.get('cache_materialization') != 'model_decision_only_current_source_identity':
                issues.append(_issue('cache_rebinding_marker_missing', item_id))
            if inference or any(item_usage.get(k) != 0 for k in TOKEN_FIELDS):
                issues.append(_issue('cache_usage_not_zero', item_id, item_usage))
        elif inference:
            counts['inference_calls'] += 1
        else:
            counts['deterministic_results'] += 1
            if any(item_usage.get(k) != 0 for k in TOKEN_FIELDS):
                issues.append(_issue('non_inference_usage_not_zero', item_id, item_usage))

        activity = result.get('activity')
        if activity == 'unknown':
            counts['unknown_proposals'] += 1
        else:
            counts['known_proposals'] += 1
            quote = result.get('evidence_quote')
            source_text = source.get('source_text', '')
            if not isinstance(quote, str) or not quote.strip() or quote.casefold() not in source_text.casefold():
                issues.append(_issue('known_proposal_without_exact_source_quote', item_id,
                                     {'activity': activity, 'quote': quote}))
            else:
                semantic_candidates.append({
                    'item_id': item_id, 'proposal_id': source['proposal_id'],
                    'workout_id': source['workout_id'],
                    'source_block_id': source['source_block_id'],
                    'source_item_id': source['source_item_id'],
                    'source_text': source_text,
                    'source_text_sha256': source['source_text_sha256'],
                    'activity': activity, 'proposal_activity': activity,
                    'evidence_quote': quote,
                    'annotation_origin': result.get('annotation_origin'),
                    'cache_hit': cache_hit,
                    'semantic_review_state': 'not_reviewed',
                })

    sample = _stable_sample(semantic_candidates, sample_size, manifest['manifest_sha256'])
    return {
        'schema_version': 1,
        'audit_kind': 'completed_atomic_source_item_job',
        'job_id': job_id,
        'job_state': job['state'],
        'passed': not issues,
        'catalog_sha256': manifest['catalog_sha256'],
        'source_item_manifest_sha256': manifest['manifest_sha256'],
        'counts': counts,
        'usage': usage,
        'runtime_eligibility': {
            'required': False,
            'eligible_items': sum(1 for issue in issues
                                  if issue['code'] == 'runtime_eligible_not_false'),
            'promotion_performed': False,
        },
        'semantic_high_confidence_sample': {
            'selection': 'sha256(manifest_sha256 + NUL + proposal_id), ascending',
            'candidate_rule': 'known activity with non-empty exact source quote',
            'candidate_count': len(semantic_candidates),
            'requested_size': sample_size,
            'sample_size': len(sample),
            'evidence_status': 'deterministic_source_level_sample_for_human_review_not_labels',
            'items': sample,
        },
        'issues': issues,
    }


def semantic_review_queue(report):
    """Convert the stable sample into the exact local review-tool contract."""
    sample = report['semantic_high_confidence_sample']['items']
    return {
        'schema_version': 1,
        'job_id': report['job_id'],
        'count': len(sample),
        'selection': report['semantic_high_confidence_sample']['selection'],
        'evidence_status': 'stored_model_proposals_for_review_not_labels',
        'runtime_eligible': False,
        'items': sample,
    }


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--db', required=True, type=Path)
    parser.add_argument('--job', required=True)
    parser.add_argument('--sample-size', type=int, default=40)
    parser.add_argument('--output', type=Path)
    parser.add_argument('--review-output', type=Path)
    args = parser.parse_args(argv)
    report = audit_source_item_job(args.db, args.job, args.sample_size)
    body = json.dumps(report, indent=2, sort_keys=True) + '\n'
    if args.output:
        args.output.write_text(body)
    else:
        print(body, end='')
    if args.review_output:
        args.review_output.write_text(json.dumps(
            semantic_review_queue(report), indent=2, sort_keys=True) + '\n')
    return 0 if report['passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
