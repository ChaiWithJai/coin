# Activity proposal review

Run the local review against the checked timed-unknown queue:

```sh
python3 tools/activity_review/app.py \
  evidence/workout-delivery-20261002/timed-unknown-review-queue-current.json
```

Open `http://127.0.0.1:5400/`. Decisions save automatically beside the queue. Pass accepts the displayed proposal, including `unknown`. Fail means the notes should name the corrected registered activity and cite the exact source wording. Defer when a boxer or more context is needed.

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

## Bundle an approved runtime overlay

Review labels alone can never enter the app. After review, a human creates a
separate `runtime_drill_human_approval` file naming the reviewer and UTC review
time and approving both the movement and its measurement recipe. Each approval
also carries the SHA-256 of the exact saved label returned by
`decision_sha256()` in `compile_runtime_overlay.py`.

The build must export a `coin_runtime_segment_manifest` for one lesson. It pins
the exact `WorkoutCatalog.json` hash and lists every generated runtime segment,
in index order, with its source block and optional source item. Then run:

```sh
python3 tools/activity_review/compile_runtime_overlay.py \
  queue.json review.json human-approval.json runtime-manifest.json \
  ios/WorkoutCatalog.json \
  ios/ReviewedRuntimeDrills-basic-w1-d1.json
```

The compiler rejects unsigned decisions, deferred or unknown movements,
abstract movement families, incomplete lesson coverage, changed decisions,
source lineage drift, and catalog drift. It emits one versioned proposal per
runtime segment. Add that exact output file to the Coin target resources for a
release build. Coin checks all hashes, wording, registered movement versions,
recipes, target uniqueness, and complete lesson coverage again at load time. A
rejected overlay leaves the immutable source workout unchanged. No current
model output or local review is approved automatically.
