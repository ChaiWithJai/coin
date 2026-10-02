"""Round harness: the GPU-box half of Coin's workload.

The phone labels exchanges with rules (onsets, phases, faults). This harness adds:
  1. Decision model (Bonsai 9B, typed question): per exchange, cue / quiet / review,
     with probabilities read from one forward pass (label tokens + logprobs), no free text.
  2. Report model (Bonsai 9B, the cap for Coin): one observation, one interpretation, one constraint for next round,
     one prediction, one drill from the library, in the round-report contract.
Every model call and its inputs/outputs come back as trace stages for the outbox.
"""
import json, math, os, time, urllib.request

SMALL_URL = os.environ.get('COIN_SMALL_URL', 'http://127.0.0.1:8712')   # 9B decision model (beat the 4B on the intervention question)
REPORT_URL = os.environ.get('COIN_REPORT_URL', 'http://127.0.0.1:8712')  # 9B writes the report (the family's cap for Coin)

DRILLS = {
    'guard_return': {'fault': 'rear_hand_low',
        'fr': 'Jab isolé au ralenti, main arrière collée au visage, puis retour en garde avant le suivant. 3 séries de 10.',
        'en': 'Slow single jabs with the rear hand glued to your face, back to guard before the next one. 3 sets of 10.'},
    'reset_hold': {'fault': 'no_reset',
        'fr': 'Après chaque combinaison, reviens en garde et tiens deux secondes avant de repartir.',
        'en': 'After every combination, return to guard and hold for two seconds before going again.'},
    'exit_angle': {'fault': 'no_exit',
        'fr': 'Jab-direct, puis un pas de côté ou un pivot sur le pied avant. Ne reste jamais sur la ligne.',
        'en': 'Jab-cross, then a side step or a pivot on the lead foot. Never stay on the line.'},
    'probe_then_commit': {'fault': 'commit_without_probe',
        'fr': 'Ouvre chaque échange par un jab ou une feinte, puis engage la combinaison.',
        'en': 'Open every exchange with a jab or a feint, then commit to the combination.'},
}

CONSTRAINTS = {
    'guard_return': {'fr': 'Main arrière au visage sur chaque jab.', 'en': 'Rear hand on your face for every jab.'},
    'reset_hold': {'fr': 'Reviens en garde après chaque combinaison.', 'en': 'Back to guard after every combination.'},
    'exit_angle': {'fr': 'Sors de la ligne après chaque combinaison.', 'en': 'Leave the line after every combination.'},
    'probe_then_commit': {'fr': 'Ouvre chaque échange avec le jab.', 'en': 'Open every exchange with the jab.'},
}
ISSUE_FOR_FAULT = {'no_reset': 'reset_hold', 'no_exit': 'exit_angle', 'rear_hand_low': 'guard_return'}


def main_issue(fault_counts, commits, n):
    """The one thing to fix, chosen by code: the most frequent fault, or committing without probing."""
    ranked = sorted(fault_counts.items(), key=lambda kv: (-kv[1], list(ISSUE_FOR_FAULT).index(kv[0])))
    if commits / max(n, 1) >= 0.6 and (not ranked or ranked[0][1] < commits): return 'probe_then_commit'
    return ISSUE_FOR_FAULT[ranked[0][0]] if ranked else 'probe_then_commit'


CHOICES = {
    'opener': {'A': 'probe', 'B': 'commit'},
    'intervention': {'A': 'cue', 'B': 'quiet', 'C': 'review'},
}
SYSTEM_SMALL = ("You label one boxing exchange from a phone camera's pose data. Taxonomy: an exchange has initiation, "
                "interaction, termination and reset. A probe is a light lead-hand action (jab, feint) that measures distance "
                "before power; a commit starts with the rear hand or goes straight to power. Coaching policy: cue = a short live "
                "correction is worth it now; quiet = nothing useful to say; review = save it for the between-round report. "
                "Answer with a single letter.")
QUESTIONS = {
    'opener': 'Was the opening of this exchange a probe or a commit?\nA) probe\nB) commit\nAnswer:',
    'intervention': 'What should the coach do about this exchange?\nA) cue\nB) quiet\nC) review\nAnswer:',
}


def _post(url, body, timeout):
    req = urllib.request.Request(url + '/v1/chat/completions', json.dumps(body).encode(), {'Content-Type': 'application/json'})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.load(r)


def describe(ex):
    hands = ' '.join(p['hand'] for p in ex['punches'])
    gaps = [ex['punches'][i + 1]['atMs'] - ex['punches'][i]['atMs'] for i in range(len(ex['punches']) - 1)]
    faults = [f for f, on in (('rear_hand_low', any(p['rearHandLow'] for p in ex['punches'])),
                              ('no_reset', ex.get('resetMs') is None),
                              ('no_exit', len(ex['punches']) >= 2 and ex['lateralShift'] < 0.35)) if on]
    first = 'lead hand (jab)' if ex['punches'][0]['hand'] == 'lead' else 'rear hand (cross or power)'
    return (f"opening punch: {first}; punches in order: {hands} ({len(ex['punches'])}); gaps between punches (ms): {gaps or 'none'}; "
            f"peak speeds (shoulder widths/s): {[p['peakSpeed'] for p in ex['punches']]}; "
            f"back to guard after: {str(ex['resetMs']) + ' ms' if ex.get('resetMs') is not None else 'not seen'}; "
            f"lateral move after: {ex['lateralShift']} shoulder widths; rule faults: {faults or 'none'}; "
            f"live cue already given: {ex.get('cue') or 'none'}"), faults


def ask_small(question, exchange_text):
    """One forward pass; probabilities over the answer letters from the first token's logprobs."""
    body = {'messages': [{'role': 'system', 'content': SYSTEM_SMALL},
                         {'role': 'user', 'content': f'Exchange: {exchange_text}\n\n{QUESTIONS[question]}'}],
            'max_tokens': 1, 'temperature': 0, 'logprobs': True, 'top_logprobs': 10,
            'chat_template_kwargs': {'enable_thinking': False}}
    t = time.perf_counter()
    raw = _post(SMALL_URL, body, 20)
    letters = CHOICES[question]
    probs = {k: 0.0 for k in letters}
    try:
        for cand in raw['choices'][0]['logprobs']['content'][0]['top_logprobs']:
            tok = cand['token'].strip().rstrip(')').upper()
            if tok in probs: probs[tok] += math.exp(cand['logprob'])
    except (KeyError, IndexError, TypeError):
        pass
    total = sum(probs.values())
    if total <= 0:  # fall back to the generated letter
        tok = (raw['choices'][0]['message'].get('content') or '').strip()[:1].upper()
        probs = {k: (1.0 if k == tok else 0.0) for k in letters}; total = 1.0
    best = max(probs, key=probs.get)
    return letters[best], round(probs[best] / total, 3), {
        'name': f'small_model.{question}', 'span_type': 'LLM', 'inputs': body,
        'outputs': {'label': letters[best], 'probs': {letters[k]: round(v / total, 3) for k, v in probs.items()}},
        'duration_ms': (time.perf_counter() - t) * 1000}


def report(summary, labels, language):
    exchanges = summary['exchanges']
    n = len(exchanges)
    fault_counts = {}
    for ex in exchanges:
        for f in describe(ex)[1]: fault_counts[f] = fault_counts.get(f, 0) + 1
    probes = sum(1 for e in exchanges if e['opener'] == 'probe')   # facts come from the phone's rules
    agree = sum(1 for e, l in zip(exchanges, labels) if e['opener'] == l['opener'])
    facts = {'round': summary['round'], 'duration_s': summary['duration_s'], 'exchanges': n,
             'punches': sum(len(e['punches']) for e in exchanges),
             'probe_openers': probes, 'commit_openers': n - probes, 'fault_counts': fault_counts,
             'reset_rate': round(sum(1 for e in exchanges if e.get('resetMs') is not None) / max(n, 1), 2),
             'live_cues': [e['cue'] for e in exchanges if e.get('cue')],
             'small_model_opener_agreement': round(agree / max(n, 1), 2),
             'flagged_for_review': [l['id'] for l in labels if l['intervention'] == 'review']}
    drill_id = main_issue(fault_counts, n - probes, n)
    plain = {'no_reset': 'not back to guard', 'no_exit': 'stayed on the line after the combination',
             'rear_hand_low': 'rear hand dropped on the jab', 'commit_without_probe': 'opened without a jab'}
    facts['fault_counts'] = {plain[k]: v for k, v in fault_counts.items()}
    facts['main_issue'] = plain[DRILLS[drill_id]['fault']]
    lang = 'French' if language == 'fr' else 'English'
    schema = {'type': 'object', 'required': ['observation', 'interpretation', 'prediction'],
              'properties': {'observation': {'type': 'string'}, 'interpretation': {'type': 'string'}, 'prediction': {'type': 'string'}}}
    body = {'model': 'bonsai-9b', 'temperature': 0.2, 'max_tokens': 300, 'chat_template_kwargs': {'enable_thinking': False},
            'response_format': {'type': 'json_schema', 'json_schema': {'name': 'round_report', 'schema': schema}},
            'messages': [
                {'role': 'system', 'content':
                    f"You are a boxing coach writing a between-round report in {lang} for a boxer training alone with a phone camera. "
                    "Use only the round facts given (pose tracking: punch onsets, exchange phases, guard and reset checks). "
                    f"The one thing to fix next round is already chosen: {facts['main_issue']}, and the boxer will be told: "
                    f"\"{CONSTRAINTS[drill_id]['en']}\". Write one short, plain sentence per field, consistent with that choice, in everyday boxing words (no underscores or field names). "
                    "observation: the numbers that show the problem. interpretation: why it matters in a fight. "
                    "prediction: what next round's numbers should show if the boxer does it."},
                {'role': 'user', 'content': json.dumps(facts, ensure_ascii=False)}]}
    t = time.perf_counter()
    model = 'bonsai-9b'
    raw = _post(REPORT_URL, body, 60)
    out = json.loads(raw['choices'][0]['message']['content'])
    out.update(constraint=CONSTRAINTS[drill_id][language], drill_id=drill_id, _model=model)
    stage = {'name': f'{model}.round_report', 'span_type': 'LLM', 'inputs': body, 'outputs': out,
             'duration_ms': (time.perf_counter() - t) * 1000}
    return out, facts, stage


def run(summary):
    """Returns (response for the phone, trace stages)."""
    t0 = time.perf_counter()
    language = summary['language']
    stages = [{'name': 'phone.exchange_rules', 'span_type': 'TOOL',
               'inputs': {'round': summary['round'], 'drill_id': summary.get('drill_id'), 'stance': summary['stance']},
               'outputs': {'exchanges': summary['exchanges']}, 'duration_ms': 0}]
    labels, small_ok = [], True
    for ex in summary['exchanges'][:40]:
        text, _ = describe(ex)
        try:   # the opener is a geometric fact the phone's rules already know; the model answers the judgment question only
            opener, p1 = ex['opener'], 1.0
            intervention, p2, s2 = ask_small('intervention', text)
            stages.append(s2)
        except Exception as e:  # small model down: keep the rule labels, say so in the trace
            small_ok = False
            opener, p1, intervention, p2 = ex['opener'], 1.0, 'review' if describe(ex)[1] else 'quiet', 1.0
            stages.append({'name': 'small_model.unavailable', 'span_type': 'TOOL', 'inputs': {}, 'outputs': {'error': type(e).__name__}, 'duration_ms': 0})
        labels.append({'id': ex['id'], 'opener': opener, 'intervention': intervention, 'confidence': round(min(p1, p2), 3)})
    out, facts, stage = report(summary, labels, language)
    stages.append(stage)
    response = {'observation': out['observation'], 'interpretation': out['interpretation'], 'constraint': out['constraint'],
                'prediction': out['prediction'], 'drill': DRILLS[out['drill_id']][language], 'labels': labels,
                'models': ['rules'] + (['bonsai-9b'] if small_ok else []) + [out.pop('_model')],
                'latency_ms': int((time.perf_counter() - t0) * 1000)}
    return response, stages, facts
