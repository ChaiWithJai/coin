# Coin backend

`pipeline.py` implements the rules baseline for cue freshness, ordering and cooldown. It traces each window and its evidence check to MLflow. This is not Laya inference or computer vision. Only user-confirmed observations can speak in this baseline.

Run tests with the existing lab environment:

```sh
/Users/jaibhagat/code/prismml/bonsai-lab/.venv/bin/python -m pytest outputs/coin/backend/test_pipeline.py -q
/Users/jaibhagat/code/prismml/bonsai-lab/.venv/bin/python outputs/coin/backend/verify_trace.py
```

The second command intentionally emits a synthetic fixture trace in `boxing-app-inference`, reads it back, and verifies parent and child spans. Production deployment still requires authentication, clock synchronization, bounded session state, concurrent stream isolation, model adapters and real video evidence.

`POST /v1/live/pose-window` accepts a bounded, authenticated aggregate from an iPhone MediaPipe sample: session/block/request IDs, sequence, time, language, landmark counts, framing state, pose processing delay, and extractor version. It writes one idempotent event to the durable outbox with a `visual_perception` stage. The response is always `silence` with reason `movement_classifier_unvalidated`; no punch, exchange, or completed drill is inferred. Request IDs deduplicate retries and reject conflicting payloads. The iOS app has an opt-in aggregate sender. It persists selected samples and their language locally before sending, then retries pending samples with the same request IDs on a later batch or live-screen visit. A synthetic request has been read back from MLflow; no physical-device request has been verified.

Run `verify_pose_window_trace.py` with the local Bonsai lab Python environment to verify a synthetic authenticated HTTP request, outbox delivery, and an MLflow trace read-back. The fixture does not exercise a phone camera or movement classifier.
