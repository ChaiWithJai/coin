# Activity proposal review

Run the local review against the checked timed-unknown queue:

```sh
python3 tools/activity_review/app.py \
  evidence/workout-delivery-20261002/timed-unknown-review-queue-current.json
```

Open `http://127.0.0.1:5400/`. Decisions save automatically beside the queue. Pass means the source evidence should remain unknown. Fail means the notes should name the activity supported by the source and cite the wording. Defer when a boxer or more context is needed.

Labels are bound to the exact queue hash and stay `runtimeEligible=false`. This tool has no promotion endpoint and does not write to Coin or MLflow.
