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

The subsequent fault-card and warm-up sound guards are included in the signed build installed and launched on Lakshmi. The bundled catalog matches the source snapshot byte for byte; see `../evidence/workout-delivery-20261002/verification.json`. A completed physical workout has not yet been observed. The final signed build, including the privacy copy, was installed and launched. Installation does not establish that a complete gym workout succeeds.

## Batch evidence and next experiment

The first catalog annotation batch is intentionally paused and its proposals are not promoted. Its SQLite record confirms 63 completed items, 17 failed items, and 451 pending items. The worker exited and released its queue claim. "Completed" here means that a response passed its output checks, not that its label was correct.

Observed mistakes include `12 JUMP SQUATS` labeled as shadowboxing with a recovery cue, stretches labeled as strength, and solo stance work labeled as partner work. Preserve the failed baseline at `../../../outputs/batch-catalog-full/1790977581543407000/`. Its job ID is `713968f685b5c7c9611567c8800a89e9023623b5e9b795acb57110c754692dd7`. The saved `annotations.json`, `result.json`, and MLflow attempts support the next comparison.

The revised candidate uses exact source activity names where available, then asks a small model for a bounded decision only where context remains unresolved. It checks the decision against source evidence. A workout prescription cannot establish that the athlete performed an exchange phase, so prescription annotations keep that phase unspecified.

The first targeted comparison completed eight items, using four model calls and four source rules. Seven matched the analyst's development expectations; one solo stance instruction returned `unknown` instead of the expected shadowboxing label. The expected labels are explicitly not human gold labels. The result at `../../../outputs/batch-catalog-targeted/1790977965615835000/result.json` records all eight delivered telemetry items. The small set demonstrates corrections to known failures and a remaining abstention, not general recognition accuracy. Independent label review remains necessary before promoting any batch output. Retain the old database and create a separate candidate database; do not resume the paused baseline to accumulate more unreliable labels.

A follow-up source spelling correction handles `PUCNHES` in the existing material. Replaying the eight saved responses then matched all eight development expectations without another model call; see `postprocessor-replay.json` beside the targeted result. A separate full-catalog candidate has completed all 531 items with no processing failures and has exported all 531 events with 531 finished runs read back from MLflow in `../../../outputs/batch-catalog-full/1790978065968604000/`. The earlier failed baseline remains separate. Processing completion does not establish label accuracy. The batch made 191 model calls and recorded 29,647 surfaced tokens; 147 classifications remain unknown. See the committed batch receipt in `../evidence/workout-delivery-20261002/`. Actual monetary cost is unknown. The MongoDB archive backup failed because its service was unavailable, so no verified archive restore is claimed. Review the labels before promoting anything. The paused failed baseline remains intact.

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

## Checkpoint publication

Commit each major milestone with its implementation, verification, remaining limitations, and evidence. On October 2 GitHub reported `ChaiWithJai/coin` as public, despite earlier build-log notes saying private. Local checkpoint commits are allowed. Remote pushes await Jai's explicit choice because the standing instruction prohibits public publication. Do not treat older private-repository notes as current visibility evidence.

## French report regression

The real coordinator smoke request succeeded and queued offline review, but returned an English interpretation for a French request. The failed response and its trace are preserved in `contextual-round-smoke.json`. Program and freestyle reports now constrain their interpretation to localized, evidence-supported sentences, with a separate output gate and preserved raw model response. The report only has counts and cannot assess technique or drill adherence. This deliberately limits the current report; it does not establish specialized boxing reasoning. Regression tests cover wrong-language output and zero detections without claiming inactivity. Source workout titles and instructions remain the original English.

The fresh real coordinator smoke after deployment passed the French sentence check and durable offline enqueue. Its separate request and evidence are in `contextual-round-locale-fixed.json`; it is synthetic input over the actual private service and model, not phone footage. The server suite now contains 22 passing tests.

## October 2 completion and identity checkpoint

The verified target is native Coin (`com.coinboxing.prototype`) from this repository. Free Alpha (`com.prismml.freealpha`) is a separate AI Engineer app. Both run in separate simulators, so use the explicit Coin iPhone 11 UDID from `AGENTS.md`. The phone install receipt, bundle/catalog hashes, and process path are in `../evidence/workout-delivery-20261002/completion-checkpoint.json`.

The full manual source workout and short timed freestyle completion paths now pass simulator tests and persist after restart. Manual source work is present in the recap and log with its original prescription. Round reports can be reopened after the last round, even when no rest follows. The saved pending-report card was tested with a DEBUG-only local fixture because the simulator cannot generate camera exchanges. That fixture never calls GB10. See `../design-review/workout-completion-20261002/README.md` for exact tests and screenshots.

The first real synthetic French round succeeded through the coordinator but used an English interpretation. The next offline smoke succeeded yet exposed singular-count grammar (“1 échanges”). Both failures remain saved. The corrected French live and offline paths returned “1 échange et 1 départ de coup” from the actual GB10 service. The offline job processed only its own two items and returned a current-version count-supported report through the authenticated status endpoint. Its three MLflow events and trace IDs were read back. Old unrestricted batch reports are withheld from the result endpoint; original stored outputs and traces remain. Offline classifications remain proposals. No measured technique quality or gym workout is claimed.

The current phone build opens on Lakshmi, but a real training session has not been completed on the device. The source workout copy is still the original English. Next evidence should come from a normal phone placement and a real session before tuning cues or promoting model proposals. Monetary inference and Codex billing remain unknown; exposed development usage is recorded separately in MLflow.

## Source items in the camera workout, 2 October 2026

The source catalog contained manual sections with many exercises or combinations, but Coin previously offered one Done control for the whole section. Coin now splits 22 unambiguous sections into 218 individual manual steps. Each step retains the exact source item ID and text, parent section ID, group prescription, and item demo links. Sections with ambiguous text keep their original single-step behavior. This does not add exercise recognition or invent a timer.

The first test run preserved a parser failure on three combination lists containing plus signs, a URL test that missed the source section fragment, and an ambiguous UI selector. After those corrections, 46 unit tests and 5 Coin UI tests passed. The UI test completed all ten items in basic week 1 day 6, resumed on Pallof Press after relaunch, and reopened saved progress. Result: `/tmp/coin-workout-derived/Logs/Test/Test-Coin-2026.10.02_18-59-02--0400.xcresult`.

A signed `com.coinboxing.prototype` build was installed and launched on Lakshmi at 19:02 local time. The receipt is in `../evidence/workout-delivery-20261002/source-item-checkpoint.json`. No real camera workout was performed in this pass, and no phone-origin inference was found in the recent MLflow audit. Source instructions remain English; the app controls support French and English. The current exposed Codex usage snapshot is MLflow run `486c5a2b252c4c3aa094813568b6e8c9`; billed cost and an equivalent estimate remain unknown.

## Timed round focus and session-end evidence, 2 October 2026

Five reviewed virtual-pad source sections now assign their exact item text to each of 25 three-minute rounds. Coin shows and requests speech for the current focus. The heading's demo link stays available as shared section context. The compiler checks exact section IDs and source text before mapping; changed lists fall back to the full original section. No model proposal becomes a live cue. The other 22 expanded manual sections remain intact. Fifteen catalog tests pass, including timing, rests, source IDs and fallback.

An ended workout now leaves a stable local receipt even when it has no detected exchange and therefore no round report. The authenticated private `/v1/workout/completion` route accepts identical retries once and queues a separate `workout_completion` MLflow span without GPU inference. It records explicit runtime origin, catalog version, source item and section IDs, timer or manual exit reasons, and cue requests. These are evidence of app activity, not exercise adherence or confirmed speech playback. The receipt contains no pose data, film, notes or reflection; pose sharing remains separate and optional. Older sessions without an origin remain `unknown`.

The integrated simulator run passed 53 unit and five existing UI tests. The new virtual-pad UI test passed separately after correcting its accessibility selector and rest-screen handling. Forty-four server tests pass. A synthetic zero-exchange receipt was accepted twice under one ID and read back as one finished MLflow run `01165b440b3141cea018729d1a1eca8e`, trace `tr-ba2382ebe156db4f8ceae9b90a81574d`. The Coin service and existing LAN/tailnet forwarder remain healthy. The signed new Coin build installed and launched on Lakshmi at 19:22. Exact evidence, including failed attempts, is in `../evidence/workout-delivery-20261002/pad-round-receipt-checkpoint.json`.

The next real workout should produce a `physical_device` completion receipt and let Jai judge cue audibility and usefulness at normal phone placement. No new physical workout or movement-recognition accuracy was established here. Source workout instructions remain English; billed cost remains unknown.

## Runtime activity instance checkpoint, 2 October 2026

The workout section remains the source prescription. Each active block now has an append-only activity instance with a stable ID, source block/item lineage, selection provenance, and a versioned measurement recipe. Separate warm-up activities have separate slots. The five reviewed generic conditioning sections and the default mobility segment offer a compact on-camera choice. The boxer can choose jumping jacks, burpees, box jumps, squat jumps, squats, lunges, mobility, or name another movement. Source instructions stay visible. A mixed prescribed circuit does not gain a substitution picker.

Only the existing squat and lunge angle trackers produce unvalidated rep candidates. The exchange tracker produces unvalidated boxing candidates. Other choices record elapsed time only; the app does not claim to recognize burpees, jumps, or custom movements. Custom names stay in local session storage. The completion receipt sends only the `custom` key, choice provenance, and clock-only recipe. The source catalog maps four exact, reviewed strength items to existing counters; similar exercise names are not inferred from text. Corrected camera aspect ratio is applied to knee angles and wrist travel, but normal phone-placement recognition accuracy remains unmeasured.

The integrated simulator run passed 72 tests, including six UI flow tests; 45 server tests passed. A synthetic receipt was accepted by the private GB10 service and read back as MLflow run `02f7b621a61e482ba75b3638649a6b27`, trace `tr-32389f81969fffdbc89f9c7920fb7785`, with an `activity_instances` output and `elapsed_only` burpees recipe. This proves lineage transport, not exercise performance. The build was installed on Lakshmi at 19:45, but iOS denied the launch check because the phone was locked. The user still needs to try a real round at a normal phone angle before we tune recognition or cues. Exposed Codex usage snapshot run: `3ebc310f6f4649fdaa564b5ad9f3e4db`. Actual billed cost remains unknown.

## Evidence correction and exercise review, 2 October 2026

The activity picker now closes its loop in the app: selected movements and candidate repetitions appear in the immediate recap and saved session review in French and English. A completed preparation slot remains complete when the boxer substituted a movement. When a segment has several choices, its entire elapsed time is left unattributed instead of being assigned to the final choice; individual movement durations still need explicit interval accounting. The focused choose, switch, finish, review and relaunch UI replay passed in both languages. No physical workout is claimed from that fixture.

Two actual round traces exposed a false coaching pattern: all 16 resets in one round and seven of eight in another were absent measurements, yet the old policy treated them as failed resets. Reset evidence now distinguishes observed, fully covered but not detected, and unobservable. Missing joints, long frame gaps and early round endings abstain. A valid observed reset stays latched after later movement. Legacy nulls become unknown, so the 23 missing measurements in those traces no longer qualify for reset faults. This is a deterministic replay of saved summaries, not proof of technique correctness or current MediaPipe accuracy. The other guard, exit and opener heuristics remain unchanged. See `../evidence/workout-delivery-20261002/reset-evidence-replay-checkpoint.json`.

The source batch had annotated whole sections even though the app now advances through individual exercises. A bounded normalization job generated separate, versioned proposals for the ten items in basic week one day six, preserving exact source item IDs, group prescriptions and demos. Only the exact Squat maps to the existing unvalidated candidate counter; the other nine receive clock-only recipes. All ten separate TOOL traces finished in MLflow, with zero model calls. This is source interpretation, not a claim that any exercise was performed. The earlier section-level batch remains the baseline. See `../evidence/workout-delivery-20261002/source-item-batch-checkpoint.json`. Billed and infrastructure costs remain unknown.
