# Agentic development for Coin

Continue toward the full goal: let Jai perform the workouts from [boxing.dharmicdata.org](https://boxing.dharmicdata.org) or freestyle in Coin, with small models assigned narrow jobs, useful batch analysis, and an observable improvement loop. Keep the noir camera experience as the main interface. The goal remains active; passing a build or finishing the import does not establish that the whole experience works at the gym.

## The recovered workflow

The source is section 5, "How it gets built: development as an agent trajectory," in [Jai's master plan](https://gist.github.com/ChaiWithJai/74b46c72aefdba34bc1e4dbcb00b3387). The local copy is `/Users/jaibhagat/code/bonsai-gen/gists/5-boxing/BOXING-MASTER-PLAN.md`, beginning at line 145. Sections 6 and 7 define runtime measurements and the division of work between models.

The working sequence below paraphrases that source. No separate named mathematical formula was found, so do not attribute one to Jai. If Jai provides the intended formula, update this file while preserving the full product goal.

1. Read the current code, source material, labels, and traces before choosing the next change. Recover the intended workout and drill instead of substituting generic boxing advice.
2. Give agents independent pieces of the workload, with explicit file ownership and acceptance evidence. Integrate their results into one app and one experiment history.
3. Build a small usable change, then run it. Preserve source prescriptions, model outputs, and human corrections as distinct records.
4. Record what changed, what failed, and what remains at each meaningful check-in. Join model and app events by session, source block, request, and model version.
5. Inspect the resulting experience and trace failures. Group related failures, choose the next change, and compare it against the same cases plus held-out sessions.
6. Install the app on the phone and use the result in a workout. Gym feedback and the next round's evidence determine whether the change helped.

Measure exchanges against replay, cue usefulness and delay, and whether the next-round constraint helps. A model's valid JSON or probability does not establish a correct boxing judgment. MLflow owns experiment records; the app owns workout progress and observations. Exposed development usage is recorded separately from product inference. Actual charges, estimates, and unknown amounts stay separate, and hidden reasoning is not captured.

## Verified state on October 2

Coin imports both five-week programs as 70 source days. The catalog preserves the original instructions, source section IDs, hashes, and links. Explicit round prescriptions become timers; ambiguous or repetition-based work remains manual. Source boxing and freestyle retain their own context instead of inheriting the jab, combination, angle-exit fault policy.

The final simulator run passed 40 unit tests and 3 UI tests. The UI tests reached the final day of both programs, advanced a manual warm-up into its exact two-minute round, and restored that round after relaunch. They also checked French and English freestyle. The result is `/tmp/coin-workout-derived/Logs/Test/Test-Coin-2026.10.02_17-47-10--0400.xcresult`. Screenshots are in `../design-review/workout-flow-20261002/`. The simulator had no camera, so this evidence covers navigation, timers, language controls, and persistence rather than tracking quality.

The source instructions and source speech remain English, with that fact stated in the program picker. French controls and freestyle cues work. Reviewed French source instructions remain to be produced. Mixed circuits remain manual, and users open the instruction sheet for the full prescription and demonstrations. Exercise-level guidance needs further work where a source section contains several exercises.

Source session summaries now show actual elapsed time without inventing a total duration. Completion requires the recorded work and rests to finish; time spent in a manual step cannot by itself complete the program. The home screen restores the selected source workout title. Freestyle no longer displays a tactical probe/commit judgment.

The subsequent fault-card and warm-up sound guards are included in the signed build installed and launched on Lakshmi. The bundled catalog matches the source snapshot byte for byte; see `../evidence/workout-delivery-20261002/verification.json`. A completed physical workout has not yet been observed. An initial signed build was installed, and the final privacy copy update is being rebuilt. Check the current installation result in `../BUILD-LOG.md` before claiming that the latest source is on the phone or that the gym experience is verified.

## Batch evidence and next experiment

The first catalog annotation batch is intentionally paused and its proposals are not promoted. Its SQLite record confirms 63 completed items, 17 failed items, and 451 pending items. The worker exited and released its queue claim. "Completed" here means that a response passed its output checks, not that its label was correct.

Observed mistakes include `12 JUMP SQUATS` labeled as shadowboxing with a recovery cue, stretches labeled as strength, and solo stance work labeled as partner work. Preserve the failed baseline at `../../../outputs/batch-catalog-full/1790977581543407000/`. Its job ID is `713968f685b5c7c9611567c8800a89e9023623b5e9b795acb57110c754692dd7`. The saved `annotations.json`, `result.json`, and MLflow attempts support the next comparison.

The revised candidate uses exact source activity names where available, then asks a small model for a bounded decision only where context remains unresolved. It checks the decision against source evidence. A workout prescription cannot establish that the athlete performed an exchange phase, so prescription annotations keep that phase unspecified.

The first targeted comparison completed eight items, using four model calls and four source rules. Seven matched the analyst's development expectations; one solo stance instruction returned `unknown` instead of the expected shadowboxing label. The expected labels are explicitly not human gold labels. The result at `../../../outputs/batch-catalog-targeted/1790977965615835000/result.json` records all eight delivered telemetry items. The small set demonstrates corrections to known failures and a remaining abstention, not general recognition accuracy. Evaluate independent source cases before expanding the batch. Retain the old database and create a separate candidate database; do not resume the paused baseline to accumulate more unreliable labels.

A follow-up source spelling correction handles `PUCNHES` in the existing material. Replaying the eight saved responses then matched all eight development expectations without another model call; see `postprocessor-replay.json` beside the targeted result. A separate full-catalog candidate has completed all 531 items with no processing failures and is exporting to MLflow in `../../../outputs/batch-catalog-full/1790978065968604000/`. The earlier failed baseline remains separate. Processing completion does not establish label accuracy. Check the database for current status and review its labels before promoting anything. The paused failed baseline remains intact.

## Resume commands

Start from the current checkout and inspect changes before editing:

```sh
cd /Users/jaibhagat/Documents/Codex/2026-09-25/i-x20/outputs/coin
git status --short
git log -5 --oneline
cat BUILD-LOG.md
cat docs/WORKOUT-SOURCE-IMPORT.md
```

Run the deterministic source and queue checks without making inference calls:

```sh
cd server
python3 -m unittest test_workout_catalog.py
/Users/jaibhagat/code/prismml/bonsai-lab/.venv/bin/python -m unittest discover -s tests
cd ..
```

Inspect the paused baseline without restarting it:

```sh
python3 server/batch_jobs.py \
  --db ../batch-catalog-full/1790977581543407000/batch.sqlite \
  status --job-id 713968f685b5c7c9611567c8800a89e9023623b5e9b795acb57110c754692dd7
```

Inspect the separate full-catalog candidate using its existing database:

```sh
python3 server/batch_jobs.py \
  --db ../batch-catalog-full/1790978065968604000/batch.sqlite \
  status --job-id 80386470c1590fecb7d02e43e34dae734e2233b811e308c18e8f4d8203ae5829
```

Verify the existing worker process before resuming inference. Do not run `work/batch_catalog_full.py` as a resume command, because it creates another experiment database. Resumption of an interrupted candidate must retain its database and reclaim the shared queue only after the old worker has exited. A dedicated command that preserves those checks remains to be added.

Run the app regression flow on the existing simulator:

```sh
cd ios
xcodegen generate --spec project.yml
xcodebuild -workspace Coin.xcworkspace -scheme Coin \
  -destination 'platform=iOS Simulator,id=CB5D7882-F35E-469E-980B-5729D3C0F7D4' \
  -derivedDataPath /tmp/coin-workout-derived \
  -only-testing:CoinTests -only-testing:CoinUITests/WorkoutFlowTests test
```

Sync the current task's exposed usage with the existing MLflow environment:

```sh
cd /Users/jaibhagat/Documents/Codex/2026-09-25/i-x20
/Users/jaibhagat/code/prismml/bonsai-lab/.venv/bin/python work/sync_usage.py
```

After changing the candidate, rerun the bounded comparison outside a live workout:

```sh
cd /Users/jaibhagat/Documents/Codex/2026-09-25/i-x20
/Users/jaibhagat/code/prismml/bonsai-lab/.venv/bin/python work/batch_catalog_targeted.py
```

The script writes a new experiment directory, claims the shared GB10 queue, and yields to live Coin activity. Read its saved comparison and model outputs before choosing whether to run more source blocks.

The UI tests use separate app storage through the DEBUG-only `COIN_TRAINING_DIRECTORY` token and do not clear Jai's workout history. Rebuild and install on the physical phone only after the final code is tested. Preserve unrelated GB10 services and give live coaching priority over batch work. Inspect MLflow trace outputs after each continued development pass; a successful export alone does not establish that the coaching improved.
