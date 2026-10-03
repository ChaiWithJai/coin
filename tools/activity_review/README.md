# Activity proposal review

Run the local review against the checked timed-unknown queue:

```sh
python3 tools/activity_review/app.py \
  evidence/workout-delivery-20261002/timed-unknown-review-queue-current.json
```

Open `http://127.0.0.1:5400/`. Decisions save automatically beside the queue. Pass means the source evidence should remain unknown. Fail means the notes should name the activity supported by the source and cite the wording. Defer when a boxer or more context is needed.

Labels are bound to the exact queue hash and stay `runtimeEligible=false`. This tool has no promotion endpoint and does not write to Coin or MLflow.

## Compile reviewed examples

Complete every item before compiling. A pass accepts `unknown`. For a fail, enter
notes as a JSON object whose evidence quote is copied exactly from the displayed
source text:

```json
{"activity":"frontal_stance","evidence_quote":"FR0NTAL STANCE DRILL"}
```

Choose one or more whole workouts as the held-out evaluation split, then compile:

```sh
python3 tools/activity_review/compile_dataset.py \
  evidence/workout-delivery-20261002/timed-unknown-review-queue-current.json \
  evidence/workout-delivery-20261002/timed-unknown-review-queue-current-review.json \
  /tmp/coin-reviewed-activity \
  --eval-workout basic-w1-d1
```

The command writes `record.json`, `review.json`, and `dataset.json`. It rejects
open or deferred items, prose corrections, evidence that is absent from the
source text, queue or source hash drift, unknown evaluation workouts, and a split
without both train and evaluation sessions. Every source workout stays wholly in
one split. The dataset says `training_performed: false`; this command prepares
reviewed inputs and does not train, evaluate, promote, or deploy a model.
